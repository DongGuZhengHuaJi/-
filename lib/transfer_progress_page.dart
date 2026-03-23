// import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

class TransferProgressPage extends StatefulWidget {
  final Socket socket;
  final Stream<List<int>> fileDataStream; // 用于传输文件数据的流
  final bool isSender;
  final String filePath; 
  final String receiveDir; // 接收方指定的目录
  final String fileName;
  final int fileSize;   // 总大小，用于算百分比

  const TransferProgressPage({
    super.key,
    required this.socket,
    required this.fileDataStream,
    required this.isSender,
    required this.filePath,
    required this.receiveDir,
    required this.fileName,
    required this.fileSize,
  });

  @override
  State<TransferProgressPage> createState() => _TransferProgressPageState();
}

class _TransferProgressPageState extends State<TransferProgressPage> {
  int _processedBytes = 0;
  double _progress = 0.0;
  bool _isDone = false;
  String _errorMsg = "";

  @override
  void initState() {
    super.initState();
    _startTransfer();
  }

  void _startTransfer() async {
    try {
      if (widget.isSender) {
        await _sendAction();
      } else {
        await _receiveAction();
      }
    } catch (e) {
      if (mounted) setState(() => _errorMsg = "传输中断: $e");
    }
  }

// --- 发送逻辑 ---
  Future<void> _sendAction() async {
    File file = File(widget.filePath);
    int totalSize = widget.fileSize;
    int sentBytes = 0;

    try {
      final fileStream = file.openRead();
      
      await for (List<int> chunk in fileStream) {
        widget.socket.add(chunk); // 往 Socket 缓冲区塞数据
        sentBytes += chunk.length;

        if (mounted) {
          setState(() {
            _progress = sentBytes / totalSize;
          });
        }

        await widget.socket.flush(); 
      }
      
      _complete();
    } catch (e) {
      if (mounted) setState(() => _errorMsg = "发送失败: $e");
    }
  }

  // --- 接收逻辑 ---
  Future<void> _receiveAction() async {

    IOSink? sink;
    try {

      final directory = Directory(widget.receiveDir);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      String savePath = path.join(widget.receiveDir, widget.fileName);
      File saveFile = File(savePath);
      sink = saveFile.openWrite();
     
      // 这里的 fileDataStream 是从 Service 里的 StreamController 传过来的管道
      Stream<List<int>> dataStream = widget.fileDataStream;

      DateTime _lastUpdateTime = DateTime.now();

      // 在 _receiveAction 的循环中
      await for (List<int> chunk in dataStream) {
        sink.add(chunk);
        _processedBytes += chunk.length;

        // 每隔 100ms 或者传输完成时才更新 UI
        DateTime now = DateTime.now();
        if (now.difference(_lastUpdateTime).inMilliseconds > 100 || _processedBytes >= widget.fileSize) {
          if (mounted) {
            setState(() {
              _progress = _processedBytes / widget.fileSize;
            });
          }
          _lastUpdateTime = now;
        }
        
        if (_processedBytes >= widget.fileSize) break;
      }
    } catch (e) {
      if (mounted) setState(() => _errorMsg = "接收出错: $e");
    } finally {
      // 无论成功失败，都要关闭文件句柄，类似 C++ 的 RAII
      await sink?.close();
      _complete();
    }
  }


  void _complete() {
    if (mounted) setState(() => _isDone = true);
  }

  @override
  void dispose() {
    widget.socket.destroy(); // 销毁页面即断开连接（RAII）
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isSender ? "正在发送" : "正在接收")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(widget.fileName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            
            // 进度条
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: LinearProgressIndicator(value: _progress, minHeight: 10),
            ),
            
            const SizedBox(height: 10),
            Text("${(_progress * 100).toStringAsFixed(1)} %"),
            
            if (_isDone) const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Text("✅ 传输成功", style: TextStyle(color: Colors.green, fontSize: 18)),
            ),
            if (_errorMsg.isNotEmpty) Text(_errorMsg, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}