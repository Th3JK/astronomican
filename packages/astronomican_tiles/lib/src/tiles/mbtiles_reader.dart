import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Reads an `.mbtiles` file — metadata and tile blobs — without SQLite.
///
/// A read-only subset of the SQLite file format, in plain Dart: enough to
/// walk a table's b-tree and decode its records. A native sqlite3 library would
/// need a DLL on Windows and a native-assets build everywhere; this needs
/// nothing, and the tool only ever reads two tables.
///
/// Understands both layouts in use: tilemaker's plain `tiles` table, and
/// Planetiler's compact `tiles_shallow` + `tiles_data` behind a `tiles` view.
final class MbtilesReader {
  MbtilesReader._(this._file, this._pageSize, this._usable);

  /// Opens [file].
  ///
  /// Throws [FormatException] for anything that is not a readable SQLite
  /// database — including one with an unmerged write-ahead log beside it,
  /// whose latest pages this reader would not see.
  static Future<MbtilesReader> open(File file) async {
    final wal = File('${file.path}-wal');
    if (await wal.exists() && await wal.length() > 0) {
      throw FormatException(
        '${file.path} has an open write-ahead log; close whatever is writing it',
      );
    }
    final raf = await file.open();
    final header = await raf.read(100);
    if (header.length < 100 ||
        ascii.decode(header.sublist(0, 15), allowInvalid: true) !=
            'SQLite format 3') {
      await raf.close();
      throw FormatException('${file.path} is not an SQLite database');
    }
    final data = ByteData.sublistView(header);
    var pageSize = data.getUint16(16);
    if (pageSize == 1) pageSize = 65536;
    final reserved = header[20];
    final encoding = data.getUint32(56);
    if (encoding > 1) {
      await raf.close();
      throw FormatException('${file.path} is not UTF-8 encoded');
    }
    return MbtilesReader._(raf, pageSize, pageSize - reserved);
  }

  final RandomAccessFile _file;
  final int _pageSize;
  final int _usable;
  List<_SchemaRow>? _schema;

  /// The `metadata` table, as name → value.
  Future<Map<String, String>> metadata() async {
    final table = (await _schemaRows()).where(
      (r) => r.type == 'table' && r.name == 'metadata',
    );
    if (table.isEmpty) return const {};
    final columns = _columns(table.first.sql);
    final nameAt = columns.indexOf('name');
    final valueAt = columns.indexOf('value');
    return {
      for (final row in _rows(table.first.rootPage))
        if (row.length > nameAt && row[nameAt] is String)
          row[nameAt]! as String: '${row.length > valueAt ? row[valueAt] : ''}',
    };
  }

  /// Every stored tile's data, once each — deduplicated tiles appear once.
  Iterable<Uint8List> tileBlobs() sync* {
    final schema = _schemaRowsSync();
    final data = schema.where(
      (r) => r.type == 'table' && r.name == 'tiles_data',
    );
    final plain = schema.where((r) => r.type == 'table' && r.name == 'tiles');
    final table = data.isNotEmpty
        ? data.first
        : (plain.isNotEmpty ? plain.first : null);
    if (table == null) return;
    final at = _columns(table.sql).indexOf('tile_data');
    if (at < 0) return;
    for (final row in _rows(table.rootPage)) {
      if (row.length > at && row[at] is Uint8List) yield row[at]! as Uint8List;
    }
  }

  /// Closes the file.
  Future<void> close() => _file.close();

  Future<List<_SchemaRow>> _schemaRows() async => _schemaRowsSync();

  List<_SchemaRow> _schemaRowsSync() => _schema ??= [
    for (final row in _rows(1))
      if (row.length >= 5)
        _SchemaRow(
          type: '${row[0]}',
          name: '${row[1]}',
          rootPage: row[3] is int ? row[3]! as int : 0,
          sql: row[4] is String ? row[4]! as String : '',
        ),
  ];

  Uint8List _page(int number) {
    _file.setPositionSync((number - 1) * _pageSize);
    final page = _file.readSync(_pageSize);
    if (page.length != _pageSize) {
      throw FormatException('Page $number is past the end of the file');
    }
    return page;
  }

  /// Every record of the table b-tree rooted at [root], in rowid order.
  Iterable<List<Object?>> _rows(int root) sync* {
    if (root <= 0) return;
    final page = _page(root);
    final start = root == 1 ? 100 : 0;
    final data = ByteData.sublistView(page);
    final type = page[start];
    final cells = data.getUint16(start + 3);
    switch (type) {
      case 0x05: // interior table page
        for (var i = 0; i < cells; i++) {
          final cell = data.getUint16(start + 12 + i * 2);
          yield* _rows(data.getUint32(cell));
        }
        yield* _rows(data.getUint32(start + 8));
      case 0x0d: // leaf table page
        for (var i = 0; i < cells; i++) {
          var at = data.getUint16(start + 8 + i * 2);
          final (size, n1) = _varint(page, at);
          at += n1;
          final (_, n2) = _varint(page, at);
          at += n2;
          yield _record(_payload(page, at, size));
        }
      default:
        throw FormatException(
          'Unexpected b-tree page type $type on page $root',
        );
    }
  }

  /// A table cell's payload, following overflow pages when it spills.
  Uint8List _payload(Uint8List page, int at, int size) {
    final u = _usable;
    final x = u - 35;
    if (size <= x) return Uint8List.sublistView(page, at, at + size);
    final m = ((u - 12) * 32 ~/ 255) - 23;
    final k = m + ((size - m) % (u - 4));
    final local = k <= x ? k : m;
    final out = BytesBuilder(copy: false)
      ..add(Uint8List.sublistView(page, at, at + local));
    var next = ByteData.sublistView(page).getUint32(at + local);
    var remaining = size - local;
    while (remaining > 0 && next != 0) {
      final overflow = _page(next);
      final take = remaining < u - 4 ? remaining : u - 4;
      out.add(Uint8List.sublistView(overflow, 4, 4 + take));
      remaining -= take;
      next = ByteData.sublistView(overflow).getUint32(0);
    }
    return out.takeBytes();
  }

  static List<Object?> _record(Uint8List b) {
    final (headerSize, n) = _varint(b, 0);
    var at = n;
    final types = <int>[];
    while (at < headerSize) {
      final (t, m) = _varint(b, at);
      types.add(t);
      at += m;
    }
    final data = ByteData.sublistView(b);
    var pos = headerSize;
    final values = <Object?>[];
    for (final t in types) {
      switch (t) {
        case 0:
          values.add(null);
        case >= 1 && <= 6:
          final width = const [0, 1, 2, 3, 4, 6, 8][t];
          var v = 0;
          for (var i = 0; i < width; i++) {
            v = (v << 8) | b[pos + i];
          }
          // Sign-extend from the stored width.
          if (width < 8 && b[pos] & 0x80 != 0) v -= 1 << (width * 8);
          values.add(v);
          pos += width;
        case 7:
          values.add(data.getFloat64(pos));
          pos += 8;
        case 8:
          values.add(0);
        case 9:
          values.add(1);
        case >= 12 when t.isEven:
          final length = (t - 12) ~/ 2;
          values.add(Uint8List.sublistView(b, pos, pos + length));
          pos += length;
        case >= 13:
          final length = (t - 13) ~/ 2;
          values.add(
            utf8.decode(b.sublist(pos, pos + length), allowMalformed: true),
          );
          pos += length;
        default:
          throw FormatException('Unknown SQLite serial type $t');
      }
    }
    return values;
  }

  /// An SQLite varint at [at]: the value and how many bytes it took.
  static (int, int) _varint(Uint8List b, int at) {
    var v = 0;
    for (var i = 0; i < 8; i++) {
      final byte = b[at + i];
      v = (v << 7) | (byte & 0x7f);
      if (byte & 0x80 == 0) return (v, i + 1);
    }
    return ((v << 8) | b[at + 8], 9);
  }

  /// A table's column names, from its `CREATE TABLE` statement.
  static List<String> _columns(String sql) {
    final open = sql.indexOf('(');
    final close = sql.lastIndexOf(')');
    if (open < 0 || close <= open) return const [];
    final body = sql.substring(open + 1, close);
    final columns = <String>[];
    var depth = 0;
    final current = StringBuffer();
    void flush() {
      final definition = current.toString().trim();
      current.clear();
      if (definition.isEmpty) return;
      final first = definition.split(RegExp(r'\s+')).first;
      final upper = first.toUpperCase();
      // Table constraints, not columns.
      if (const {
        'PRIMARY',
        'UNIQUE',
        'CHECK',
        'FOREIGN',
        'CONSTRAINT',
      }.contains(upper)) {
        return;
      }
      columns.add(first.replaceAll(RegExp(r'''^["'`\[]|["'`\]]$'''), ''));
    }

    for (final ch in body.split('')) {
      if (ch == '(') depth++;
      if (ch == ')') depth--;
      if (ch == ',' && depth == 0) {
        flush();
      } else {
        current.write(ch);
      }
    }
    flush();
    return columns;
  }
}

class _SchemaRow {
  _SchemaRow({
    required this.type,
    required this.name,
    required this.rootPage,
    required this.sql,
  });

  final String type;
  final String name;
  final int rootPage;
  final String sql;
}
