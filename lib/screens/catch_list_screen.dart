import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/catch.dart';
import 'add_catch_screen.dart';

class CatchListScreen extends StatefulWidget {
  const CatchListScreen({super.key});

  @override
  State<CatchListScreen> createState() => _CatchListScreenState();
}

class _CatchListScreenState extends State<CatchListScreen> {
  List<Catch> _catches = [];

  @override
  void initState() {
    super.initState();
    _loadCatches();
  }

  Future<void> _loadCatches() async {
    final data = await DatabaseHelper.instance.getCatches();
    setState(() {
      _catches = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Catches')),
      body: ListView.builder(
        itemCount: _catches.length,
        itemBuilder: (context, index) {
          final catchItem = _catches[index];
          return ListTile(
            title: Text(catchItem.fishType),
            subtitle: Text(
              '${catchItem.lengthCm} cm\n${catchItem.notes ?? ''}'
),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddCatchScreen()),
          );
          _loadCatches(); // refresh after returning
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}