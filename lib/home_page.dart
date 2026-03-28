import 'dart:async';
import 'transfer_service.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'discover_service.dart';
import 'countdown_dialog.dart';
import 'send_request_dialog.dart';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'discover_page.dart';
import 'home_provider.dart';
import 'transfer_page.dart';
import 'remote_connect_page.dart';

var logger = Logger(); 

// class HomePage extends StatefulWidget {

//   final String userName;
//   const HomePage({super.key, required this.userName});


//   @override
//   State<HomePage> createState() => _HomePageState();

// } 

// class _HomePageState extends State<HomePage> {
//   late DiscoverService _discoverService;
//   late TransferService _transferService;
//   late TransferHistoryManager _historyManager;
//   int _currentIndex = 0; // 当前页面索引
//   String _myIp = "获取中...";

//   StreamSubscription? _transferSubscription;

//   @override
//   void initState() {
//     super.initState();
//     _discoverService = DiscoverService();
//     _transferService = TransferService();
//     _historyManager = TransferHistoryManager();
//     _initNetwork();
//     _transferSubscription = _transferService.onMessageReceived.listen((task) {
//       if(task.message["type"] == "request_to_send"){
//         logger.i("收到传输请求: ${task.message}");
//         _showReceiveRequestDialog(task);
//       }
//     });
//   }

//   Future<void> _initNetwork() async {
//     await _discoverService.start();
//     await _transferService.start();
//     if (!mounted) return;
//     setState(() {
//       _myIp = _discoverService.myInfo?.ip ?? "未知";
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     // 定义三个主页面
//     final List<Widget> _pages = [
//       _buildDiscoverPage(), // 附近设备
//       const Center(child: Text("传输任务（开发中...）")), 
//       const Center(child: Text("传输历史（开发中...）")),
//     ];

//     return Scaffold(
//       appBar: AppBar(
//         title: const Text("文件投递助手"),
//         centerTitle: true,
//         actions: [
//           // 💡 关键：手动单播按钮
//           IconButton(
//             icon: const Icon(Icons.add_link),
//             onPressed: () => _showManualConnectDialog(context),
//             tooltip: "单播探测",
//           ),
//         ],
//       ),
//       body: _pages[_currentIndex], // 根据索引切换页面
//       bottomNavigationBar: BottomNavigationBar(
//         currentIndex: _currentIndex,
//         onTap: (index) => setState(() => _currentIndex = index),
//         items: const [
//           BottomNavigationBarItem(icon: Icon(Icons.near_me), label: "附近"),
//           BottomNavigationBarItem(icon: Icon(Icons.swap_horiz), label: "传输"),
//           BottomNavigationBarItem(icon: Icon(Icons.history), label: "历史"),
//         ],
//       ),
//     );
//   }

//   // --- UI 构建方法 ---

//   Widget _buildDiscoverPage() {
//     return Column(
//       children: [
//         _buildInfoBanner(), // 顶部自己的信息
//         Expanded(child: _buildPeerList()), // 邻居列表
//       ],
//     );
//   }

//   Widget _buildInfoBanner() {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
//       decoration: BoxDecoration(
//         color: Theme.of(context).colorScheme.primaryContainer,
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text("本机身份: ${widget.userName}", style: const TextStyle(fontWeight: FontWeight.bold)),
//           Text("当前 IP: $_myIp", style: const TextStyle(fontSize: 12, color: Colors.grey)),
//         ],
//       ),
//     );
//   }

//   Widget _buildPeerList() {
//     return ValueListenableBuilder<Map<String, PeerInfo>>(
//       valueListenable: _discoverService.peersNotifier,
//       builder: (context, peers, child) {
//         if (peers.isEmpty) {
//           return const Center(child: Text("当前局域网未发现邻居，尝试点击右上角单播探测"));
//         }
//         return ListView.builder(
//           itemCount: peers.length,
//           itemBuilder: (context, index) {
//             var peer = peers.values.elementAt(index);
//             return Card(
//               margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
//               child: ListTile(
//                 leading: const CircleAvatar(child: Icon(Icons.laptop)),
//                 title: Text(peer.name),
//                 subtitle: Text(peer.ip),
//                 trailing: const Icon(Icons.chevron_right),
//                 onTap: () => _onPeerSelected(peer),
//               ),
//             );
//           },
//         );
//       },
//     );
//   }

//   // --- 功能逻辑 ---

//   void _showManualConnectDialog(BuildContext context) {
//     final controller = TextEditingController();
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text("单播探测 (局域网内)"),
//         content: TextField(
//           controller: controller,
//           decoration: const InputDecoration(hintText: "输入对方 IP (例如 10.145.162.67)"),
//           keyboardType: TextInputType.number,
//         ),
//         actions: [
//           TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
//           ElevatedButton(
//             onPressed: () {
//               final ip = controller.text.trim();
//               if (ip.isNotEmpty) {
//                 //调用你在 DiscoverService 里写的单播探测方法
//                 _discoverService.probePeerByIp(ip); 
//                 Navigator.pop(context);
//               }
//             },
//             child: const Text("开始探测"),
//           ),
//         ],
//       ),
//     );
//   }

//   void _showSendRequestDialog(PeerInfo peer, String path, String name, int size) {
//     showDialog(context: context, 
//     builder: (context) => SendRequestDialog(
//         targetIp: peer.ip,
//         myName: widget.userName,
//         path: path,
//         name: name,
//         size: size,
//         service: _transferService,
//         onAccept: (socket) {
//           logger.i("对方接受了传输请求，准备发送文件...");
//           _navigateToTransferPage(socket, fileDataStream: Stream.empty(), isSender: true, filePath: path, fileName: name, fileSize: size);
//         }
//       )
//     );
//   }
//   void _showReceiveRequestDialog(TransferTask task) {
//     showDialog(context: context, 
//     builder: (context) => CountdownDialog(
//         title: "传输请求",
//         content: Text("收到从 ${task.message['from']} 发来的文件传输请求"),
//         initialSeconds: 10,
//         acceptLabel: "接受",
//         rejectLabel: "拒绝",
//         onAccept: () async {
//           _navigateToTransferPage(
//             task.client, 
//             fileDataStream: task.fileDataStream,
//             isSender: false, 
//             receiveDir: Config.receivedFilesDir, 
//             fileName: task.message['name'], 
//             fileSize: task.message['size']);
              
//             _transferService.acceptTransferRequest(task);
//         },
//         onReject: () async {
//           _transferService.rejectTransferRequest(task);
//         },
//       )
//     );
//   }

//   void _onPeerSelected(PeerInfo peer) async {
//     try{
//         logger.i("选中邻居: ${peer.name} at ${peer.ip}");
      
//         final typeGroup = XTypeGroup(label: 'files', extensions: ['*']);
//         final file = await openFile(acceptedTypeGroups: [typeGroup]);
//         if (file != null) {
//           String path = file.path;
//           String name = file.name;
//           int size = await File(path).length();
//           logger.i("选择的文件: $name ($size bytes) at $path");
//           _showSendRequestDialog(peer, path, name, size);
//         } else {
//           logger.i("文件选择被取消");
//         }
//       }
//       catch(e){
//         logger.e("发生错误: $e");
//     }
//   }

//   void _navigateToTransferPage(Socket socket, {Stream<List<int>>? fileDataStream, required bool isSender, String? filePath, String? fileName, int? fileSize, String? receiveDir}) {
//     Navigator.push(context, MaterialPageRoute(
//       builder: (context) => TransferProgressPage(
//         socket: socket,
//         fileDataStream: fileDataStream??Stream.empty(), // 发送端没有数据流，传一个空流占位
//         isSender: isSender,
//         filePath: filePath ?? "",
//         fileName: fileName ?? "未知文件",
//         fileSize: fileSize!,
//         receiveDir: receiveDir ?? Config.receivedFilesDir,
//       )
//     ));

//   }

//   Widget _buildTransferHistoryPage(){
//     return Column(
//       children: [
        
//       ],
//     );
//   }

//   @override
//   void dispose() {
//     _discoverService.dispose();
//     _transferService.dispose();
//     _transferSubscription?.cancel();
//     super.dispose();
//   }
// }

class HomePage extends StatefulWidget {
  final String userName;
  final String myUuid;
  const HomePage({super.key, required this.userName, required this.myUuid});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late HomeProvider _provider;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _provider = HomeProvider(widget.userName);
    _provider.init();
    
    // 绑定 Provider 的回调到 UI 弹窗
    _provider.onReceiveRequestTrigger = (task) => _showReceiveRequestDialog(task);
    
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> subPages = [
      DiscoverSubPage(provider: _provider, onPeerSelected: _onPeerSelected),
      RemoteConnectPage(myUuid: widget.myUuid, myName: widget.userName, provider: _provider), // 远程连接页面
      TransferPage(provider: _provider), // 传输页面，显示传输任务
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("文件投递助手", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_link),
            onPressed: () => _showManualConnectDialog(),
          ),
        ],
      ),
      body: IndexedStack( // 使用 IndexedStack 切换页面可以保持子页面的滚动状态
        index: _currentIndex,
        children: subPages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.near_me), label: "附近"),
          BottomNavigationBarItem(icon: Icon(Icons.swap_horiz), label: "远程"),
          BottomNavigationBarItem(icon: Icon(Icons.swap_horiz), label: "传输"),
        ],
      ),
    );
  }

  // --- 具体的 UI 交互逻辑 (Dialog 等) ---
  void _onPeerSelected(PeerInfo peer) async {
    // 1. 选择文件逻辑
    // 2. 调用 _showSendRequestDialog
     try{
        logger.i("选中邻居: ${peer.name} at ${peer.ip}");
      
        final typeGroup = XTypeGroup(label: 'files', extensions: ['*']);
        final file = await openFile(acceptedTypeGroups: [typeGroup]);
        if (file != null) {
          String path = file.path;
          String name = file.name;
          int size = await File(path).length();
          logger.i("选择的文件: $name ($size bytes) at $path");
          _showSendRequestDialog(peer, path, name, size.toDouble());
        } else {
          logger.i("文件选择被取消");
        }
      }
      catch(e){
        logger.e("发生错误: $e");
    }
  }

  void _showSendRequestDialog(PeerInfo peer, String path, String name, double size) {
    showDialog(
      context: context, 
      builder: (context) => SendRequestDialog(
        targetIp: peer.ip,
        myName: widget.userName,
        path: path,
        name: name,
        size: size,
        service: _provider.transferService,
        onAccept: (socket) {
          _startTransferInternal(path, name, size.toDouble(), true, socket);
        }
      )
    );
  }

  void _showReceiveRequestDialog(TransferTask task) {
    showDialog(context: context, 
    builder: (context) => CountdownDialog(
        title: "传输请求",
        content: Text("收到从 ${task.message['from']} 发来的文件传输请求"),
        initialSeconds: 10,
        acceptLabel: "接受",
        rejectLabel: "拒绝",
        onAccept: () async {
          _provider.transferService.acceptTransferRequest(task);
          _startTransferInternal(
          task.message['path'] ?? "",            // 如果没有路径，给个空字符串
          task.message['name'] ?? "未知文件",      // 确保键名 'name' 和 Python 一致
          (task.message['size'] ?? 0).toDouble(), // 确保键名 'size' 一致，并处理空值
          false, 
          task.client, 
          fileDataStream: task.fileDataStream
          );
        },
        onReject: () async {
          _provider.transferService.rejectTransferRequest(task);
        },
      )
    );
  }

  void _startTransferInternal(String filePath, String fileName, double fileSize, bool isSender, Socket socket, {Stream<List<int>>? fileDataStream}) {
    final taskInfo = TransferTaskInfo(fileName: fileName, fileSize: fileSize, isSender: isSender);
    _provider.addActiveTask(taskInfo);
    _provider.transferService.performTransfer(taskInfo, socket, filePath: filePath, dataStream: fileDataStream).then((_) {
      _provider.removeActiveTask(taskInfo);
    });
    
    setState(() => _currentIndex = 1); 
  }

  void _showManualConnectDialog() {
    // 单播探测弹窗 (调用 _provider.probeIp)
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("单播探测 (局域网内)"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "输入对方 IP (例如 10.145.162.67)"),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
          ElevatedButton(
            onPressed: () {
              final ip = controller.text.trim();
              if (ip.isNotEmpty) {
                //调用你在 DiscoverService 里写的单播探测方法
                _provider.probeIp(ip);
                Navigator.pop(context);
              }
            },
            child: const Text("开始探测"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }
}