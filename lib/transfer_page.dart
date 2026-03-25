import 'package:flutter/material.dart';
import 'home_provider.dart';
import 'transfer_history_manager.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

class TransferPage extends StatefulWidget {
  final HomeProvider provider;
  const TransferPage({super.key, required this.provider});

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  bool _isEditing = false; 
  final Set<int> _selectedIndices = {}; 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? "已选择 ${_selectedIndices.length} 项" : "传输记录"),
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.close : Icons.checklist),
            onPressed: () {
              setState(() {
                _isEditing = !_isEditing;
                _selectedIndices.clear();
              });
            },
          ),
          if (_isEditing && _selectedIndices.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              onPressed: _handleDeleteSelected,
            ),
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () => _showClearDialog(context),
            )
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.provider, 
        builder: (context, _) {
          return ValueListenableBuilder<List<TransferHistory>>(
            valueListenable: TransferHistoryManager.historyNotifier,
            builder: (context, historyList, _) {
              // 处理完全没有任务的情况
              if (widget.provider.activeTasks.isEmpty && historyList.isEmpty) {
                return _buildEmptyState();
              }

              return CustomScrollView(
                slivers: [
                  // 1. 正在传输的任务部分
                  if (widget.provider.activeTasks.isNotEmpty) ...[
                    _buildSectionHeader("正在传输"),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildActiveTaskItem(widget.provider.activeTasks[index]),
                        childCount: widget.provider.activeTasks.length,
                      ),
                    ),
                  ],

                  // 2. 传输历史部分
                  _buildSectionHeader("传输历史"),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildHistoryItem(historyList[index], index),
                      childCount: historyList.length,
                    ),
                  ),
                  
                  // 底部留白，防止被浮动按钮挡住
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildActiveTaskItem(TransferTaskInfo task) {
    return ListenableBuilder(
      listenable: task,
      builder: (context, _) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            leading: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                value: task.progress, // 使用你定义的 get progress
                strokeWidth: 3,
              ),
            ),
            title: Text(task.fileName, style: const TextStyle(fontSize: 14)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: LinearProgressIndicator(value: task.progress),
            ),
            trailing: Text(
              "${(task.progress * 100).toStringAsFixed(1)}%",
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          title, 
          style: TextStyle(
            fontWeight: FontWeight.bold, 
            color: Colors.blue.shade700,
            fontSize: 13
          )
        ),
      ),
    );
  }
  
  Widget _buildHistoryItem(TransferHistory item, int index) {
    bool isSelected = _selectedIndices.contains(index);

    return ListTile(
      onTap: () {
        if (_isEditing) {
          setState(() {
            isSelected ? _selectedIndices.remove(index) : _selectedIndices.add(index);
          });
        }
      },
      // 这里的逻辑修复：编辑模式下强制显示勾选框
      leading: _isEditing
          ? Checkbox(
              value: isSelected,
              onChanged: (val) {
                setState(() {
                  val == true ? _selectedIndices.add(index) : _selectedIndices.remove(index);
                });
              },
            )
          : CircleAvatar(
              backgroundColor: item.isSender ? Colors.blue.withOpacity(0.1) : Colors.green.withOpacity(0.1),
              child: Icon(
                item.isSender ? Icons.upload_rounded : Icons.download_rounded,
                color: item.isSender ? Colors.blue : Colors.green,
                size: 20,
              ),
            ),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text("${item.time}  ·  ${_formatSize(item.size)}"),
      
      trailing: _isEditing ? null : Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatusIcon(item.isSuccess),

          const SizedBox(width: 6),

          if(item.isSuccess&&!item.isSender)
            IconButton(
              icon: const Icon(Icons.folder_open, color: Colors.orange),
              onPressed: () {
                // 这里可以添加打开文件所在目录的逻辑
                _showFileInFolder(item.path);
              },
            ),
          ],
      ),
    );
  }

  void _handleDeleteSelected() async {
    // 调用之前修复好的删除逻辑
    await TransferHistoryManager.deleteHistorys(_selectedIndices);
    setState(() {
      _isEditing = false;
      _selectedIndices.clear();
    });
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认清空"),
        content: const Text("是否删除所有传输记录？此操作不可撤销。"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(
            onPressed: () {
              TransferHistoryManager.clearAll();
              Navigator.pop(ctx);
            },
            child: const Text("清空", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _formatSize(double bytes) {
    if (bytes < 1024) return "${bytes.toInt()} B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

  Widget _buildStatusIcon(bool success) {
    return success 
      ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
      : const Icon(Icons.error, color: Colors.red, size: 20);
  }

  Widget _buildEmptyState() {
    // 修复：当作为 body 唯一返回时，需要用 Center 包裹
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_edu, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text("还没有传输过文件哦", style: TextStyle(color: Colors.grey[400])),
        ],
      ),
    );
  }



Future<void> _showFileInFolder(String filePath) async {
  final File file = File(filePath);
  if (!await file.exists()) {
    print("文件不存在: $filePath");
    return;
  }

  try {
    if (Platform.isLinux) {
      // Ubuntu/Linux: 使用 nautilus 的 --select 参数
      // 如果不是 GNOME 环境，nautilus 可能不存在，这里可以做 fallback
      var result = await Process.run('nautilus', ['--select', filePath]);
      if (result.exitCode != 0) {
        // 如果 nautilus 失败，尝试通用打开文件夹命令
        await Process.run('xdg-open', [path.dirname(filePath)]);
      }
    } 
    else if (Platform.isWindows) {
      // Windows: 使用 explorer.exe /select
      await Process.run('explorer.exe', ['/select,', filePath]);
    } 
    else if (Platform.isMacOS) {
      // macOS: 使用 open -R
      await Process.run('open', ['-R', filePath]);
    }
  } catch (e) {
    print("打开文件位置失败: $e");
    // 最后的保底方案：尝试直接打开父目录
    try {
      await Process.run('xdg-open', [path.dirname(filePath)]);
    } catch (_) {}
  }
}
}