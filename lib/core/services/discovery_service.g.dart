// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'discovery_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$discoveryServiceHash() => r'79af1bd92c66e94ba6370e07a62220147c39f1f2';

/// See also [discoveryService].
@ProviderFor(discoveryService)
final discoveryServiceProvider = Provider<DiscoveryService>.internal(
  discoveryService,
  name: r'discoveryServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$discoveryServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DiscoveryServiceRef = ProviderRef<DiscoveryService>;
String _$peersHash() => r'8ab5df457f7c61c35443e1209744632aeda6d7a0';

/// See also [peers].
@ProviderFor(peers)
final peersProvider = AutoDisposeStreamProvider<List<Peer>>.internal(
  peers,
  name: r'peersProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$peersHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PeersRef = AutoDisposeStreamProviderRef<List<Peer>>;
String _$discoveryStateControllerHash() =>
    r'715bf3fb2a7d779f9d07061db27f02965091aae5';

/// See also [DiscoveryStateController].
@ProviderFor(DiscoveryStateController)
final discoveryStateControllerProvider =
    NotifierProvider<DiscoveryStateController, DiscoveryState>.internal(
      DiscoveryStateController.new,
      name: r'discoveryStateControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$discoveryStateControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$DiscoveryStateController = Notifier<DiscoveryState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
