import 'dart:async';
import 'package:flutter/material.dart';

class CountdownDialog extends StatefulWidget {
  final String title;
  final Widget content;
  final int initialSeconds;
  final String acceptLabel;
  final String rejectLabel;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const CountdownDialog({super.key, required this.title, required this.content, required this.initialSeconds, required this.acceptLabel, required this.rejectLabel, required this.onAccept, required this.onReject});

  @override
  State<CountdownDialog> createState() => _CountdownDialogState();
}

class _CountdownDialogState extends State<CountdownDialog> {
  late int _seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _seconds = widget.initialSeconds;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_seconds > 0) {
        if(mounted) {
          setState(() {
            _seconds--;
          });
        }
      } else {
        _handleTimeout();
      }
    });
  }

  void _handleTimeout() {
    _timer?.cancel();
    widget.onReject();
    if(mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.content,
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_outlined, color: Colors.grey),
              const SizedBox(width: 10),
              Text("$_seconds 秒后自动拒绝", style: const TextStyle(color: Colors.grey)),
            ],
            )
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _timer?.cancel();
            widget.onReject();
            Navigator.of(context).pop();
          },
          child: Text(widget.rejectLabel),
        ),
        ElevatedButton(
          onPressed: () {
            _timer?.cancel();
            if(Navigator.canPop(context)){
              Navigator.of(context).pop();
            }
            widget.onAccept();
          },
          child: Text(widget.acceptLabel),
        ),
      ]
    );
  }
}