import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stoa/src/rust/api/simple.dart';
import 'package:stoa/src/rust/api/chat.dart';
import 'package:stoa/src/rust/frb_generated.dart';
import 'package:stoa/chat_screen.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const ProviderScope(child: StoaApp()));
}

class StoaApp extends StatelessWidget {
  const StoaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stoa',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const StoaEntryPoint(),
    );
  }
}

@immutable
class AppState {
  final StoaCoreNode node;
  final ChatStore chatStore;
  final String dataDir;
  const AppState(this.node, this.chatStore, this.dataDir);
}

final appStateProvider = FutureProvider<AppState>((ref) async {
  final docs = await getApplicationDocumentsDirectory();
  final dataDir = docs.path;
  final node = await StoaCoreNode.create(dataDir: dataDir);
  final store = ChatStore(dbPath: '$dataDir/stoa_msgs.db');
  return AppState(node, store, dataDir);
});

const globalTopicHex =
    '0000000000000000000000000000000000000000000000000000000000000001';

/// Entry point: checks if profile is set up.
class StoaEntryPoint extends ConsumerWidget {
  const StoaEntryPoint({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(appStateProvider);

    return stateAsync.when(
      data: (state) {
        final name = state.node.displayName();
        if (name.isEmpty) {
          return SetupScreen(state: state);
        }
        return StoaHomePage(state: state);
      },
      loading: () => const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Starting Iroh Node...'),
            ],
          ),
        ),
      ),
      error: (err, stack) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                Text('Failed to start: $err', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// First-launch setup: enter a username.
class SetupScreen extends StatefulWidget {
  final AppState state;
  const SetupScreen({super.key, required this.state});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _controller = TextEditingController();
  String? _error;

  bool _isValid(String name) {
    final regex = RegExp(r'^[a-z0-9_]{3,24}$');
    return regex.hasMatch(name);
  }

  void _submit() {
    final name = _controller.text.trim().toLowerCase();
    if (!_isValid(name)) {
      setState(() {
        _error =
            'Username must be 3-24 chars, lowercase letters, numbers, and underscores only.';
      });
      return;
    }
    try {
      widget.state.node.setDisplayName(name: name);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => StoaHomePage(state: widget.state),
        ),
        (route) => false,
      );
    } catch (e) {
      setState(() {
        _error = 'Failed to save: $e';
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_add, size: 64, color: Colors.deepPurple),
              const SizedBox(height: 24),
              const Text(
                'Welcome to Stoa',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose a username to get started.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  labelText: 'Username',
                  hintText: 'e.g. alice_42',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                  prefixIcon: const Icon(Icons.alternate_email),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              Text(
                '3-24 chars • lowercase • letters, numbers, underscores',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _submit,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  child: Text('Continue', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Main home screen showing identity, LAN peers, and chat entry.
class StoaHomePage extends StatefulWidget {
  final AppState state;
  const StoaHomePage({super.key, required this.state});

  @override
  State<StoaHomePage> createState() => _StoaHomePageState();
}

class _StoaHomePageState extends State<StoaHomePage> {
  final List<String> _lanPeers = [];
  LanPeerHandle? _lanHandle;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _startLanDiscovery();
  }

  Future<void> _startLanDiscovery() async {
    try {
      _lanHandle = await widget.state.node.subscribeLan();
      _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _pollLanPeers();
      });
    } catch (e) {
      debugPrint('Failed to start LAN discovery: $e');
    }
  }

  Future<void> _pollLanPeers() async {
    if (_lanHandle == null) return;
    try {
      while (true) {
        final peer = await _lanHandle!.pollPeer();
        if (peer == null) break;
        if (!_lanPeers.contains(peer.peerId)) {
          setState(() {
            _lanPeers.add(peer.peerId);
          });
        }
      }
    } catch (e) {
      debugPrint('LAN peer poll error: $e');
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nodeId = widget.state.node.nodeId();
    final displayName = widget.state.node.displayName();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stoa'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Add Contact',
            onPressed: () => _showAddContactDialog(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Identity card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: Colors.green, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          displayName,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('Node ID:',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    SelectableText(
                      nodeId,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // LAN Peers section
            Row(
              children: [
                const Icon(Icons.wifi, size: 20, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'LAN Peers (${_lanPeers.length})',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _lanPeers.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search, size: 48, color: Colors.grey),
                          SizedBox(height: 8),
                          Text(
                            'Searching for peers on your network...',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _lanPeers.length,
                      itemBuilder: (context, index) {
                        final peerId = _lanPeers[index];
                        return ListTile(
                          leading: const Icon(Icons.computer,
                              color: Colors.deepPurple),
                          title: Text(
                            '${peerId.substring(0, 8)}...${peerId.substring(peerId.length - 8)}',
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                          subtitle:
                              const Text('On your network', style: TextStyle(color: Colors.green)),
                          trailing: const Icon(Icons.circle,
                              size: 12, color: Colors.green),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),

            // Chat button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  try {
                    final topicHandle = await widget.state.node
                        .joinTopic(topicHex: globalTopicHex);
                    if (!context.mounted) return;
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ProviderScope(
                        overrides: [
                          chatStoreProvider
                              .overrideWithValue(widget.state.chatStore),
                          localNodeIdProvider.overrideWithValue(nodeId),
                          topicHandleProvider.overrideWithValue(topicHandle),
                        ],
                        child: const ChatScreen(topic: 'global'),
                      ),
                    ));
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to join topic: $e')),
                    );
                  }
                },
                icon: const Icon(Icons.chat),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Enter Global Chat'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddContactDialog(BuildContext context) {
    final peerIdController = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: peerIdController,
              decoration: const InputDecoration(
                labelText: 'Peer Node ID',
                hintText: 'Paste their Node ID here',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                hintText: 'e.g. alice',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              try {
                widget.state.chatStore.addContact(
                  peerId: peerIdController.text.trim(),
                  displayName: nameController.text.trim(),
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Contact added!')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed: $e')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
