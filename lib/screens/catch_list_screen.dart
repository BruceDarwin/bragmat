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
        padding: const EdgeInsets.all(16),
        itemCount: _filteredCatches.length,
        itemBuilder: (context, index) {
          final catchItem = _filteredCatches[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: InkWell(
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
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    if (catchItem.imagePath != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(catchItem.imagePath!),
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
                      ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            catchItem.fishType,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${catchItem.lengthCm} cm',
                            style: const TextStyle(fontSize: 14),
                          ),
                          if (catchItem.dateCaught != null)
                            Text(
                              '${catchItem.dateCaught!.day}/${catchItem.dateCaught!.month}/${catchItem.dateCaught!.year}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          if (catchItem.location != null && catchItem.location!.isNotEmpty)
                            Text(
                              catchItem.location!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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