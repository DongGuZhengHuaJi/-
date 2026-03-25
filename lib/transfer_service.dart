import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import 'config.dart';
import 'dart:async';
import 'home_provider.dart';
import 'package:path/path.dart' as path;
import 'transfer_history_manager.dart';

class TransferTask{
  Socket client;
  Map<String, dynamic> message;
  final Stream<List<int>> fileDataStream; // 用于传输文件数据的流
  TransferTask({required this.client, required this.message, required this.fileDataStream});
}
class TransferService {
  
  ServerSocket? _serverSocket;
  final _controller = StreamController<TransferTask>.broadcast();
  Stream<TransferTask> get onMessageReceived => _controller.stream;

  Future<void> start() async{
    _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, Config.tcpPort);

    _serverSocket!.listen((Socket client) {
      Logger().i("New connection from ${client.remoteAddress.address}:${client.remotePort}");

      var fileDataStreamController = StreamController<List<int>>(); // 这里暂时用一个空流占位，实际使用时需要根据协议来确定何时开始传输文件数据      
      bool handledRequest = false; // 标记是否已经处理过请求
      client.listen((data) {
        if(!handledRequest){
          try{
              Map<String, dynamic> message = jsonDecode(utf8.decode(data));
              Logger().i("Received message: $message");
              handledRequest = true; // 标记已经处理过请求，后续数据将被视为文件数据
              if(message["type"] == "request_to_send"){
                Future.delayed(const Duration(milliseconds: 500), (){
                  _controller.add(TransferTask(client: client, message: message, fileDataStream: fileDataStreamController.stream));
                });
              }
              else{
                // todo: 处理其他请求
              }
          }
          catch(e){
            Logger().e("Failed to parse message: $e");
            client.close();
          }
        }
        else{
          if(!fileDataStreamController.isClosed){
            fileDataStreamController.add(data); // 将后续数据视为文件数据
            }
          }
      },
      onError: (error) {
        Logger().e("Error on connection with ${client.remoteAddress.address}:${client.remotePort} - $error");
        client.close();
      },
      onDone: () {
        Logger().i("Connection closed by ${client.remoteAddress.address}:${client.remotePort}");
        if(!fileDataStreamController.isClosed){
          fileDataStreamController.close(); // 连接关闭时确保文件数据流也被关闭
        }
      }
      );
    });
  }

  Future<Socket> connectToPeer(String ip) async {
    Socket socket = await Socket.connect(ip, Config.tcpPort);
    Logger().i("Connected to peer at $ip");
    return socket;
  }

  void acceptTransferRequest(TransferTask task){
    // 这里可以添加一些逻辑来处理接受传输请求的情况，比如准备接收文件等
    Logger().i("Accepted transfer request: ${task.message}");
    Socket client = task.client;
    Map<String, dynamic> response = {
      "type": "accept_request",
      "message": "请求已被接受，准备发送文件"
    };
    client.add(utf8.encode(jsonEncode(response)));
    client.flush();
  }

  void rejectTransferRequest(TransferTask task){
    // 这里可以添加一些逻辑来处理拒绝传输请求的情况，比如发送拒绝消息等
    Logger().i("Rejected transfer request: ${task.message}");
    Socket client = task.client;
    Map<String, dynamic> response = {
      "type": "reject_request",
      "message": "请求已被拒绝"
    };
    client.add(utf8.encode(jsonEncode(response)));
    client.flush();
    client.close();
  }

  Future<void> performTransfer(TransferTaskInfo uiTask, Socket socket, {String? filePath, Stream<List<int>>? dataStream}) async {
    String Save_Path = "";
  try {
    if (uiTask.isSender) {
        File file = File(filePath!);
        try {
          final fileStream = file.openRead();
          
          await for (List<int> chunk in fileStream) {
            socket.add(chunk); // 往 Socket 缓冲区塞数据
            uiTask.progress += chunk.length; // 更新已发送的字节数
            await socket.flush(); // 确保数据被发送出去
          }

          uiTask.isDone = true;
        }catch (e) {
          // 发送过程中发生错误
          uiTask.errorMsg = "发送失败: $e";
        }
      }else{
        try{
          final directory = Directory(Config.receivedFilesDir);
          if (!await directory.exists()) {
            await directory.create(recursive: true);
          }

          

          IOSink? sink;
        
          String savePath = path.join(Config.receivedFilesDir, uiTask.fileName);
          int count = 1;
          while (await File(savePath).exists()) {
            savePath = path.join(Config.receivedFilesDir, "copy_$count${uiTask.fileName}");
            count++;
          }

          Save_Path = savePath;
          File saveFile = File(savePath);
          sink = saveFile.openWrite();
        
          DateTime _lastUpdateTime = DateTime.now();

          // 在 _receiveAction 的循环中
          await for (List<int> chunk in dataStream!) {
            sink.add(chunk);
            uiTask.progress += chunk.length;

            // 每隔 100ms 或者传输完成时才更新 UI
            DateTime now = DateTime.now();
            if (now.difference(_lastUpdateTime).inMilliseconds > 100 || uiTask.progress >= uiTask.fileSize) {

              _lastUpdateTime = now;
            }
            
            if (uiTask.progress >= uiTask.fileSize) {
              break;
            }
          }
        }
        catch(e){
          // 接收过程中发生错误
          uiTask.errorMsg = "接收失败: $e";
        }
      }
      
      uiTask.isDone = true;
  } catch (e) {
    uiTask.errorMsg = e.toString();
  } finally {
      await TransferHistoryManager.addHistory(TransferHistory(
      name: uiTask.fileName,
      size: uiTask.fileSize,
      time: DateTime.now().toString(),
      path: Save_Path,
      isSender: uiTask.isSender,
      isSuccess: uiTask.isDone && uiTask.errorMsg == null,
      ));
    socket.destroy();
  }
}


  void dispose(){
    _serverSocket?.close();
    _controller.close();
  }
}