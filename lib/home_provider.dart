import 'dart:async';
import 'package:flutter/material.dart';
import 'discover_service.dart';
import 'transfer_service.dart';
import 'transfer_history_manager.dart';

class TransferTaskInfo extends ChangeNotifier {
  final String fileName;
  final double fileSize;
  final bool isSender;
  double _progress = 0.0;
  String _speed = "0 KB/s";
  bool isDone = false;
  String? errorMsg;
  DateTime _lastNotifyTime = DateTime.now();

  TransferTaskInfo({
    required this.fileName, 
    required this.fileSize, 
    required this.isSender
  });

  double get progress => _progress;
  set progress(double val) {
    _progress = val;
    if(DateTime.now().difference(_lastNotifyTime).inMilliseconds > 100 || _progress >= fileSize) {
      _lastNotifyTime = DateTime.now();
      notifyListeners(); // 进度变化时通知 UI
    }
  }

  String get speed => _speed;
  set speed(String val) {
    _speed = val;
    if(DateTime.now().difference(_lastNotifyTime).inMilliseconds > 100) {
      _lastNotifyTime = DateTime.now();
      notifyListeners(); // 速度变化时通知 UI
    }
  }
}

class HomeProvider extends ChangeNotifier {
  final String userName;
  final DiscoverService discoverService = DiscoverService();
  final TransferService transferService = TransferService();
  
  String myIp = "获取中...";
  StreamSubscription? _transferSubscription;

  List<TransferTaskInfo> activeTasks = []; // 当前正在传输的任务列表

  // 这里的 Function 回调让 Provider 能够“呼叫” UI 弹出对话框
  void Function(TransferTask)? onReceiveRequestTrigger;

  HomeProvider(this.userName);

  Future<void> init() async {
    await discoverService.start();
    await transferService.start();
    // await TransferHistoryManager.start(); // 加载历史记录
    //测试历史记录
    // await TransferHistoryManager.addHistory(TransferHistory(
    //   name: "测试文件.txt",
    //   size: 1024,
    //   time: DateTime.now().toString(),
    //   isSender: false,
    //   isSuccess: true
    // ));
    // await TransferHistoryManager.addHistory(TransferHistory(
    //   name: "测试文件.txt",
    //   size: 1024,
    //   time: DateTime.now().toString(),
    //   isSender: false,
    //   isSuccess: false
    // ));

    
    myIp = discoverService.myInfo?.ip ?? "未知";
    
    // 监听传输消息
    _transferSubscription = transferService.onMessageReceived.listen((task) {
      if (task.message["type"] == "request_to_send") {
        onReceiveRequestTrigger?.call(task);
      }
    });
    notifyListeners();
  }

  // 封装探测逻辑
  void probeIp(String ip) {
    discoverService.probePeerByIp(ip);
  }

  void addActiveTask(TransferTaskInfo task) {
    activeTasks.add(task);
    notifyListeners();
  }

  void removeActiveTask(TransferTaskInfo task) {
    activeTasks.remove(task);
    notifyListeners();
  }

  @override
  void dispose() {
    _transferSubscription?.cancel();
    discoverService.dispose();
    transferService.dispose();
    super.dispose();
  }
}