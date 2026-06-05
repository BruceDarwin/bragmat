import 'dart:io';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/catch.dart';
import 'add_catch_screen.dart';
import 'catch_details_screen.dart';

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
            leading: catchItem.imagePath != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(catchItem.imagePath!),
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
                  )
                : null,
            title: Text(catchItem.fishType),
            subtitle: Text(
              '${catchItem.dateCaught != null ? '${catchItem.dateCaught!.day}/${catchItem.dateCaught!.month}/${catchItem.dateCaught!.year}\n' : ''}${catchItem.lengthCm} cm\n${catchItem.notes ?? ''}'
),
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CatchDetailsScreen(catchItem: catchItem),
                ),
              );
              if (result == true) {
                _loadCatches();
              }
            },
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