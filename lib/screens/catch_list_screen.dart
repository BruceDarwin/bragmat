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
  List<Catch> _filteredCatches = [];
  String? _selectedFishTypeFilter;

  @override
  void initState() {
    super.initState();
    _loadCatches();
  }

  Future<void> _loadCatches() async {
    final data = await DatabaseHelper.instance.getCatches();
    // Sort by Date Caught, newest first
    data.sort((a, b) {
      if (a.dateCaught == null && b.dateCaught == null) return 0;
      if (a.dateCaught == null) return 1;
      if (b.dateCaught == null) return -1;
      return b.dateCaught!.compareTo(a.dateCaught!);
    });
    setState(() {
      _catches = data;
      _applyFilter();
    });
  }

  void _applyFilter() {
    if (_selectedFishTypeFilter == null || _selectedFishTypeFilter == 'All') {
      _filteredCatches = _catches;
    } else {
      _filteredCatches = _catches.where((c) => c.fishType == _selectedFishTypeFilter).toList();
    }
  }

  List<String> _getFishTypes() {
    final types = _catches.map((c) => c.fishType).toSet().toList();
    types.sort();
    return types;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Catches'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                _selectedFishTypeFilter = value;
                _applyFilter();
              });
            },
            itemBuilder: (context) {
              return [
                const PopupMenuItem(
                  value: 'All',
                  child: Text('All Fish Types'),
                ),
                ..._getFishTypes().map((type) {
                  return PopupMenuItem(
                    value: type,
                    child: Text(type),
                  );
                }),
              ];
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _filteredCatches.length,
        itemBuilder: (context, index) {
          final catchItem = _filteredCatches[index];
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
              '${catchItem.dateCaught != null ? '${catchItem.dateCaught!.day}/${catchItem.dateCaught!.month}/${catchItem.dateCaught!.year}' : ''} • ${catchItem.lengthCm} cm${catchItem.location != null && catchItem.location!.isNotEmpty ? ' • ${catchItem.location}' : ''}'
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