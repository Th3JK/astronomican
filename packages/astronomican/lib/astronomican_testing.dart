/// Fakes and fixtures for testing apps built on astronomican without a
/// device, a network or real assets.
///
/// * [sampleLevel] and [transparentPng] — levels that draw without an asset.
/// * [MemoryAssetBundle] — an asset bundle filled from a map, which counts
///   what is loaded from it, for testing pack installs.
/// * [FakePackTransport] — a pack server in memory, with ranges, failures
///   and request counting.
library;

export 'src/testing/fake_pack_transport.dart';
export 'src/testing/memory_asset_bundle.dart';
export 'src/testing/sample_levels.dart';
