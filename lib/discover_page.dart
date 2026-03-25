import 'package:flutter/material.dart';
import 'discover_service.dart'; 
import 'home_provider.dart';

class DiscoverSubPage extends StatelessWidget {
  final HomeProvider provider;
  final Function(PeerInfo) onPeerSelected;

  const DiscoverSubPage({
    super.key, 
    required this.provider, 
    required this.onPeerSelected
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 顶部信息条
        _buildInfoBanner(context),
        // 列表区域
        Expanded(
          child: ValueListenableBuilder<Map<String, PeerInfo>>(
            valueListenable: provider.discoverService.peersNotifier,
            builder: (context, peers, _) {
              if (peers.isEmpty) {
                return const Center(child: Text("搜索邻居中..."));
              }
              return ListView.builder(
                itemCount: peers.length,
                itemBuilder: (context, index) {
                  final peer = peers.values.elementAt(index);
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.devices)),
                      title: Text(peer.name),
                      subtitle: Text(peer.ip),
                      onTap: () => onPeerSelected(peer),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBanner(BuildContext context) {
  // 使用 ListenableBuilder 监听 provider 的变化
  return ListenableBuilder(
    listenable: provider, 
    builder: (context, child) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: Theme.of(context).colorScheme.surfaceVariant,
        child: Row(
          children: [
            const Icon(Icons.person_pin, size: 40),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(provider.userName, style: const TextStyle(fontWeight: FontWeight.bold)),
                // 现在当 provider.init() 完成并 notifyListeners 时，这里会自动变色/更新
                Text("IP: ${provider.myIp}", style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      );
    },
  );
}
}