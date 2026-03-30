import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:my_first_app/signaling_client.dart';
import 'countdown_dialog.dart';
import 'home_provider.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'transfer_history_manager.dart';
import 'config.dart';
import 'package:file_selector/file_selector.dart';
import 'package:logger/logger.dart';
import 'dart:async';

final logger = Logger();

class RemoteConnectPage extends StatefulWidget {
  final String myUuid;
  final String myName;
  final HomeProvider provider;

  const RemoteConnectPage({
    super.key,
    required this.myUuid,
    required this.myName,
    required this.provider,
  });

  @override
  State<RemoteConnectPage> createState() => _RemoteConnectPageState();
}

class _RemoteConnectPageState extends State<RemoteConnectPage> {
  bool isConnected = false;
  bool waitingForAnswer = false;
  bool isSending = false;
  bool cancelFile = false; // 控制是否取消正在进行的文件传输
  final _targetUuidController = TextEditingController();

  // 核心 WebRTC 对象
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  late SignalingClient _signalingClient;
  bool _hasRemoteDesc = false;

  // 状态控制变量
  String? _remoteUuid; // 锁定当前对话的目标，防止发送 Candidate 时找错人
  final Map<String, List<RTCIceCandidate>> _remoteCandidatesQueues = {};
  Completer<void>? _sendCompleter; // 用于控制发送流程的 Completer
  Completer<void>? _windowUpdateCompleter; // 用于等待窗口更新的 Completer
  Completer<void>? _transferCompleteCompleter; // 用于等待对方确认传输完成的 Completer
  List<Uint8List> _receiveQueue = []; // 用于缓存接收数据的队列
  bool _isWriting = false; // 标记当前是否正在写入文件，避免并发写入

  // IOSink? _activeSink; // 当前正在写入的文件句柄
  RandomAccessFile? _activeRaf; // 当前正在读取的文件句柄
  int _receivedWindow = 0; // 接收窗口计数器
  TransferTaskInfo? _currentUiTask; // 关联你 UI 上的进度条对象
  int _receivedBytes = 0;

  @override
  void initState() {
    super.initState();
    _hasRemoteDesc = false;

    _signalingClient = SignalingClient(myUuid: widget.myUuid);
    _signalingClient.connect("ws://localhost:3000"); // 连接信令服务器

    // 绑定信令回调
    _signalingClient.onOfferReceived = _handleOffer;
    _signalingClient.onAnswerReceived = _handleAnswer;
    _signalingClient.onCandidateReceived = _handleCandidate;
    _signalingClient.onCloseConnection = _handleCloseConnection;

    _initWebRTC();
  }

  // --- 统一的中止传输处理函数 ---
  void _abortOngoingTransfer(String reason) {
    cancelFile = true; // 告诉发送循环停下来
    
    // 1. 如果正在接收，关闭文件流
    // _activeSink?.close();
    // _activeSink = null;
    _activeRaf?.close();
    _activeRaf = null;

    // 2. 清理 UI 任务，移除进度条
    if (_currentUiTask != null) {
      _currentUiTask!.errorMsg = reason;
      widget.provider.removeActiveTask(_currentUiTask!);
      _currentUiTask = null;
    }

    // 3. 重置 UI 状态
    if (mounted) {
      setState(() {
        isSending = false; 
      });
    }
  }

  // --- 1. 初始化 WebRTC 配置 ---
  Future<void> _initWebRTC() async {
    Map<String, dynamic> configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };

    _peerConnection = await createPeerConnection(configuration);

    // 监听：发现本地路径 (Candidate)
    _peerConnection!.onIceCandidate = (candidate) {
      if (_remoteUuid != null) {
        _sendSignalingMessage({
          'type': 'candidate',
          'target': _remoteUuid,
          'from_uuid': widget.myUuid,
          'from_name': widget.myName,
          'candidate': candidate.toMap(),
        });
      }
    };

    // 监听：连接状态改变
    _peerConnection!.onConnectionState = (state) {
      debugPrint("连接状态改变: $state");
      if (mounted) {
        setState(() {
          if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
            isConnected = true;
            waitingForAnswer = false;
          } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
              state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
            isConnected = false;
          }
        });
      }
    };

    // 监听：接收方收到对方创建的 DataChannel
    _peerConnection!.onDataChannel = (channel) {
      _dataChannel = channel;
      _setupDataChannelListeners();
    };

  }

  // --- 2. 发起方逻辑 (Make Call) ---
  Future<void> _makeCall() async {
    _remoteUuid = _targetUuidController.text.trim();
    if (_remoteUuid!.isEmpty) return;

    RTCDataChannelInit init = RTCDataChannelInit();
    _dataChannel = await _peerConnection!.createDataChannel("fileTransfer", init);
    _setupDataChannelListeners();

    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    _sendSignalingMessage({
      'type': 'offer',
      'target': _remoteUuid,
      'from_name': widget.myName,
      'from_uuid': widget.myUuid,
      'sdp': offer.sdp,
    });
  }

  // --- 3. 接收方逻辑 (Handle Offer) ---
  void _handleOffer(Map<String, dynamic> data) async {
    _remoteUuid = data['from_uuid']; 

    RTCSessionDescription offer = RTCSessionDescription(data['sdp'], 'offer');
    await _peerConnection!.setRemoteDescription(offer);
    _hasRemoteDesc = true;

    _processQueuedCandidates(data['from_uuid']);

    RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    _showReceiveOfferDialog(
      data,
      () {
        _sendSignalingMessage({
          'type': 'answer',
          'target': _remoteUuid,
          'from_name': widget.myName,
          'from_uuid': widget.myUuid,
          'sdp': answer.sdp,
        });
      },
      () {
        _sendSignalingMessage({'type': 'reject', 'target': _remoteUuid});
      },
    );
  }

  // --- 4. 发起方收到应答 (Handle Answer) ---
  void _handleAnswer(Map<String, dynamic> data) async {
    if (data['type'] == 'reject') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("对方拒绝了连接请求")));
      if (mounted) setState(() => waitingForAnswer = false);
      return;
    }

    RTCSessionDescription answer = RTCSessionDescription(data['sdp'], 'answer');
    await _peerConnection!.setRemoteDescription(answer);
    _hasRemoteDesc = true;

    _processQueuedCandidates(data['from_uuid']);
  }

  // --- 5. ICE Candidate 处理 ---
  void _handleCandidate(Map<String, dynamic> data) async {
    if (data['candidate'] == null) {
      logger.w("Received empty candidate signal from ${data['from_uuid']}");
      return;
    }

    String senderUuid = data['from_uuid'];
    var candData = data['candidate'];
    RTCIceCandidate candidate = RTCIceCandidate(
      candData['candidate'],
      candData['sdpMid'],
      candData['sdpMLineIndex'],
    );

    if (!_hasRemoteDesc || _remoteUuid != senderUuid) {
      _remoteCandidatesQueues.putIfAbsent(senderUuid, () => []).add(candidate);
    } else {
      try {
        await _peerConnection!.addCandidate(candidate);
      } catch (e) {
        logger.e("添加 Candidate 失败: $e");
      }
    }
  }

  void _processQueuedCandidates(String senderUuid) async {
    List<RTCIceCandidate>? queue = _remoteCandidatesQueues[senderUuid];
    if (queue != null) {
      for (var cand in queue) {
        await _peerConnection!.addCandidate(cand);
      }
      _remoteCandidatesQueues.remove(senderUuid);
    }
  }

  // --- 6. 数据通道监听 ---
  Future<void> _setupDataChannelListeners() async {
    if (_dataChannel == null) return;

    _dataChannel!.bufferedAmountLowThreshold = 512 * 1024; // 设置传输低水位阈值 512KB

    // 监听：当缓冲区数据量低于阈值时触发，适合继续发送数据
    _dataChannel!.onBufferedAmountLow = (int bufferedAmount) {
      if(_sendCompleter != null && !_sendCompleter!.isCompleted) {
        _sendCompleter!.complete();
      }
    };

    _dataChannel!.onDataChannelState = (state) {
      debugPrint("DataChannel 状态: $state");
    };

    _dataChannel!.onMessage = (RTCDataChannelMessage message) async {
      if (message.isBinary) {
        if (_activeRaf != null && _currentUiTask != null) {
          // await _activeRaf!.writeFrom(message.binary);
          // _receivedBytes += message.binary.length;
          // _receivedWindow += message.binary.length;
          
          // _currentUiTask!.progress = _receivedBytes / _currentUiTask!.fileSize;
          
          // if(_receivedWindow >= 4 * 1024 * 1024){ // 每接收 4MB 就检查一次是否需要发送窗口更新
          //    _dataChannel!.send(RTCDataChannelMessage(jsonEncode({'type': 'window_update'})));
          //    _receivedWindow = 0;
          // }

          // if (_receivedBytes >= _currentUiTask!.fileSize) {
          //   await _finishReceiving();
          // }
          _receiveQueue.add(message.binary);
          _processReceiveQueue(); // 每次收到消息都尝试处理队列中的数据
        }
      } else {
        var info = jsonDecode(message.text);
        if (info['type'] == 'file_header') {
          _prepareToReceive(info['name'], info['size'].toDouble());
        }
        else if (info['type'] == 'file_cancel') {
          // 收到对方的取消通知，使用统一清理函数
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("对方取消了文件传输")));
          _abortOngoingTransfer("对方取消了文件传输");
        }
        else if (info['type'] == 'window_update') {
          // 对方窗口更新，允许继续发送
          if (_windowUpdateCompleter != null && !_windowUpdateCompleter!.isCompleted) {
            _windowUpdateCompleter!.complete();
          }
        }
        else if (info['type'] == 'transfer_complete') {
          // 对方确认文件已完全接收并写入磁盘
          if (_transferCompleteCompleter != null && !_transferCompleteCompleter!.isCompleted) {
            _transferCompleteCompleter!.complete();
          }
        }
      }
    };
  }

  Future<void> _prepareToReceive(String fileName, double size) async {
    _currentUiTask = TransferTaskInfo(
      fileName: fileName,
      fileSize: size,
      isSender: false,
    );
    widget.provider.addActiveTask(_currentUiTask!);

    String savePath = path.join(Config.receivedFilesDir, fileName);
    int count = 1;
    String baseName = fileName;
    while (await File(savePath).exists()) {
      savePath = path.join(Config.receivedFilesDir, "copy_${count}_$baseName");
      count++;
    }

    File file = File(savePath);
    _activeRaf = await file.open(mode: FileMode.write);
    _receivedBytes = 0;
    _receivedWindow = 0;
    _isWriting = false; // 重置写入状态
    debugPrint("开始流式接收文件: $fileName");
    if (mounted) {
      setState(() {
        isSending = true; 
        cancelFile = false; // 重置取消状态
      });
    }
  }

// 串行写入磁盘的核心队列处理机
Future<void> _processReceiveQueue() async {
  // 如果已经在写了，或者文件句柄没了，直接返回
  if (_isWriting || _activeRaf == null || _currentUiTask == null) return;
  _isWriting = true;

  try {
    // 只要队列里有数据，就一直写
    while (_receiveQueue.isNotEmpty && _activeRaf != null) {
      Uint8List data = _receiveQueue.removeAt(0);
      await _activeRaf!.writeFrom(data); // 避免并发写入，确保每次写完才更新状态
      
      _receivedBytes += data.length;
      _receivedWindow += data.length;
      
      if (mounted) {
        setState(() {
          _currentUiTask!.progress = _receivedBytes / _currentUiTask!.fileSize;
        });
      }

      // 触发窗口更新
      if (_receivedWindow >= 4 * 1024 * 1024) {
        _dataChannel!.send(RTCDataChannelMessage(jsonEncode({'type': 'window_update'})));
        _receivedWindow = 0;
      }

      // 检查是否全部接收并写入完毕
      if (_receivedBytes >= _currentUiTask!.fileSize) {
        // 关键：明确告诉发送端，我已经全部写进硬盘了！
        _dataChannel!.send(RTCDataChannelMessage(jsonEncode({'type': 'transfer_complete'})));
        await _finishReceiving();
        break; // 退出循环
      }
    }
  } catch (e) {
    logger.e("写入文件时发生致命错误: $e");
    _abortOngoingTransfer("磁盘写入失败");
  } finally {
    _isWriting = false; // 写完释放锁
  }
}

  Future<void> _finishReceiving() async {
    await _activeRaf?.close();
    _activeRaf = null;

    if (_currentUiTask != null) {
      _currentUiTask!.isDone = true;
      _transferCompleteCompleter = null;
      await TransferHistoryManager.addHistory(TransferHistory(
        name: _currentUiTask!.fileName,
        size: _currentUiTask!.fileSize,
        time: DateTime.now().toString(),
        path: path.join(Config.receivedFilesDir, _currentUiTask!.fileName),
        isSender: false,
        isSuccess: true,
      ));

      widget.provider.removeActiveTask(_currentUiTask!);
      _currentUiTask = null;
    }
    
    debugPrint("文件接收并保存完毕");
    if (mounted) setState(() => isSending = false);
  }

  Future<String> _pickFile() async {
    final typeGroup = XTypeGroup(label: 'files', extensions: ['*']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) {
      return file.path;
    } else {
      return "";
    }
  }

  Future<void> _startWebRTCTransfer(String filepath) async {
    if (filepath.isEmpty) return;

    cancelFile = false; // 每次发送前重置取消状态

    String fileName = path.basename(filepath);
    File file = File(filepath);
    int fileSize = await file.length();

    var uiTask = TransferTaskInfo(fileName: fileName, fileSize: fileSize.toDouble(), isSender: true);
    _currentUiTask = uiTask; // 记录到全局变量以便取消时访问
    widget.provider.addActiveTask(uiTask);

    _dataChannel!.send(RTCDataChannelMessage(jsonEncode({
      'type': 'file_header',
      'name': fileName,
      'size': fileSize,
    })));

    RandomAccessFile raf = await file.open(mode: FileMode.read);
    const chunk = 1024 * 64; // 64KB
    int sentSinceLastAck = 0; // 记录自上次窗口更新以来发送的字节数
    int sentBytes = 0;
    const ackThreshold = 4 * 1024 * 1024; // 每发送 4MB 就等待一次窗口更新

    try{
      while(sentBytes < fileSize && !cancelFile){
        if((_dataChannel!.bufferedAmount ?? 0) > 1024 * 1024 * 2){
          _sendCompleter = Completer<void>();
          await _sendCompleter!.future;
          _sendCompleter = null;
        }

        if(sentSinceLastAck >= ackThreshold){
          _windowUpdateCompleter = Completer<void>();
          await _windowUpdateCompleter!.future;
          _windowUpdateCompleter = null;
          sentSinceLastAck = 0;
        }

        if(cancelFile) break;
        int bytesToRead = min(chunk, fileSize - sentBytes);
        Uint8List buffer = await raf.read(bytesToRead);
        _dataChannel!.send(RTCDataChannelMessage.fromBinary(buffer));
        sentBytes += buffer.length;
        sentSinceLastAck += buffer.length;
        uiTask.progress = sentBytes / fileSize;
      }

    }catch(e){
      _sendCompleter?.complete(); // 确保如果在等待发送时发生错误，能跳出等待状态
      _windowUpdateCompleter?.complete(); // 确保如果在等待窗口更新时发生错误，能跳出等待状态
      logger.e("文件传输过程中发生错误: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("文件传输失败")));
      _abortOngoingTransfer("文件传输失败: $e");
      return;
    }

    // --- 传输结束后的状态处理 ---
    if (cancelFile) {
      // 发送取消信号给对方
      _dataChannel?.send(RTCDataChannelMessage(jsonEncode({'type': 'file_cancel'})));
      
      uiTask.errorMsg = "文件传输已取消";
      widget.provider.removeActiveTask(uiTask);
      _currentUiTask = null;
      
      await TransferHistoryManager.addHistory(TransferHistory(
        name: fileName,
        size: fileSize.toDouble(),
        time: DateTime.now().toString(),
        path: filepath,
        isSender: true,
        isSuccess: false,
      ));
      return; // 提前退出，不执行下面的成功逻辑
    }

    _transferCompleteCompleter = Completer<void>();
    // 等待对方确认传输完成（即对方文件已写入磁盘）
    await _transferCompleteCompleter!.future;
    _transferCompleteCompleter = null;

    // 成功传输逻辑
    uiTask.isDone = true;
    await TransferHistoryManager.addHistory(TransferHistory(
      name: fileName,
      size: fileSize.toDouble(),
      time: DateTime.now().toString(),
      path: filepath,
      isSender: true,
      isSuccess: true,
    ));
    
    widget.provider.removeActiveTask(uiTask);
    _currentUiTask = null;
    _sendCompleter?.complete(); // 确保如果在等待发送时完成了传输，能跳出等待状态
    _windowUpdateCompleter?.complete(); // 确保如果在等待窗口更新时完成了传输，能跳出等待状态
     debugPrint("文件发送完毕");
  }

  void _sendSignalingMessage(Map<String, dynamic> message) {
    _signalingClient.send(message);
  }

  void _showReceiveOfferDialog(Map<String, dynamic> data, Function onAccept, Function onReject) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => CountdownDialog( // 防止双重 Pop
        title: "收到连接请求",
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("来自 ${data['from_name']} 的连接请求"),
            Text("对方 UUID: ${data['from_uuid']}"),
            const SizedBox(height: 20),
            const Text("是否接受连接？"),
          ],
        ),
        initialSeconds: 10,
        acceptLabel: "接受",
        rejectLabel: "拒绝",
        onAccept: () {
          onAccept();
          if (Navigator.canPop(dialogContext)) Navigator.pop(dialogContext);
        },
        onReject: () {
          onReject();
          if (Navigator.canPop(dialogContext)) Navigator.pop(dialogContext);
        },
      ),
    );
  }

  void _handleCloseConnection(Map<String, dynamic>? data) {
    // 收到信令服务器发来的 close 消息，说明对方主动断开
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("对方已断开连接")));
    
    _abortOngoingTransfer("连接已断开"); // 断开时必须中止当前可能正在进行的传输

    _peerConnection?.close();
    _initWebRTC(); // 重新初始化

    if (mounted) {
      setState(() {
        isConnected = false;
        waitingForAnswer = false;
        isSending = false;
      });
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
  }
  
  // 处理连接按钮逻辑
  void _onConnectButtonPressed() {
    if (_targetUuidController.text.trim() == widget.myUuid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("不能连接你自己")));
      return;
    }

    if (!isConnected) {
      if (_targetUuidController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("请输入对方 ID")));
        return;
      }
      setState(() => waitingForAnswer = true);
      _makeCall();
    } else {
      // 1. 发送信令告知对方主动断开
      _sendSignalingMessage( {
        'type': 'close',
        'target': _remoteUuid,
        'from_uuid': widget.myUuid,
        'from_name': widget.myName,
      });
      
      // 2. 强行终止正在进行的任务
      _abortOngoingTransfer("已主动断开连接"); 

      // 3. 关闭底层连接
      _peerConnection?.close();
      _initWebRTC(); 

      setState(() {
        isConnected = false;
        waitingForAnswer = false;
        isSending = false;
        _remoteUuid = null;
      });
    }
  }

  @override
  void dispose() {
    _abortOngoingTransfer("连接断开，传输中止");
    
    _sendSignalingMessage( {
        'type': 'close',
        'target': _remoteUuid,
        'from_uuid': widget.myUuid,
        'from_name': widget.myName,
    });

    _targetUuidController.dispose();
    _dataChannel?.close();
    _peerConnection?.dispose();
    _signalingClient.dispose();
    super.dispose();
  }

  // --- UI 部分 ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100], 
      appBar: AppBar(
        title: const Text("P2P 远程传输"),
        elevation: 0,
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView( 
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildMyInfoCard(),
            const SizedBox(height: 20),
            _buildConnectionCard(),
            
            if (isConnected) ...[
              const SizedBox(height: 20),
              _buildFileTransferCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMyInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.indigo,
          child: Icon(Icons.person, color: Colors.white),
        ),
        title: Text(widget.myName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("我的 ID: ${widget.myUuid}"),
        trailing: IconButton(
          icon: const Icon(Icons.copy, size: 20),
          onPressed: () {
            _copyToClipboard(widget.myUuid);
          },
        ),
      ),
    );
  }

  Widget _buildConnectionCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("建立远程连接", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            TextField(
              controller: _targetUuidController,
              enabled: !isConnected && !waitingForAnswer,
              decoration: InputDecoration(
                labelText: "对方的 ID",
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                backgroundColor: isConnected ? Colors.redAccent : Colors.indigo,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _onConnectButtonPressed,
              child: waitingForAnswer
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      isConnected ? "断开连接" : "开始连接",
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileTransferCard() {
    return Card(
      color: Colors.indigo[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.indigo)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[700]),
                const SizedBox(width: 10),
                const Text("已成功建立 P2P 隧道", style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),
            if (isSending) 
              const LinearProgressIndicator(minHeight: 8, borderRadius: BorderRadius.all(Radius.circular(4))),
            const SizedBox(height: 15),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: Icon(isSending ? Icons.stop : Icons.file_upload),
              // 根据是否是发送方动态决定按钮文字
              label: Text(isSending ? (_currentUiTask?.isSender == true ? "取消发送" : "取消接收") : "选择并发送文件"),
              onPressed: () async {
                if (!isSending) {
                  // ---- 开始发送文件 ----
                  String path = await _pickFile();
                  if (path.isNotEmpty) {
                    setState(() {
                      isSending = true;
                      cancelFile = false; // 启动时重置
                    });
                    await _startWebRTCTransfer(path);
                    if (mounted) setState(() => isSending = false);
                  }
                } else {
                  // ---- 传输中执行取消逻辑 ----
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("正在终止传输...")));
                  
                  if (_currentUiTask?.isSender == true) {
                    // 发送方取消：设置标志位，退出流式读取循环
                    setState(() => cancelFile = true);
                  } else {
                    // 接收方取消：发送停止信令并清理本地
                    _dataChannel?.send(RTCDataChannelMessage(jsonEncode({'type': 'file_cancel'})));
                    _abortOngoingTransfer("已手动取消接收");
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}