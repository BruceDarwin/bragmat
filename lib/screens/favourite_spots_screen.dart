import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/favourite_spot.dart';
import 'add_edit_favourite_spot_screen.dart';

class FavouriteSpotsScreen extends StatefulWidget {
  const FavouriteSpotsScreen({super.key});

  @override
  State<FavouriteSpotsScreen> createState() => _FavouriteSpotsScreenState();
}

class _FavouriteSpotsScreenState extends State<FavouriteSpotsScreen> {
  List<FavouriteSpot> _spots = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSpots();
  }

  Future<void> _loadSpots() async {
    final spots = await DatabaseHelper.instance.getFavouriteSpots();
    if (mounted) {
      setState(() {
        _spots = spots;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteSpot(FavouriteSpot spot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Spot'),
        content: Text('Are you sure you want to delete ${spot.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && spot.id != null) {
      await DatabaseHelper.instance.deleteFavouriteSpot(spot.id!);
      await _loadSpots();
    }
  }

  String _formatCoordinates(double lat, double lng) {
    return '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favourite Fishing Spots'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _spots.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.place,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No favourite spots yet',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add your favourite fishing locations!',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[500],
                            ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _spots.length,
                  itemBuilder: (context, index) {
                    final spot = _spots[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const Icon(Icons.place, color: Colors.blue),
                        title: Text(
                          spot.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_formatCoordinates(spot.latitude, spot.longitude)),
                            if (spot.notes != null && spot.notes!.isNotEmpty)
                              Text(
                                spot.notes!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _deleteSpot(spot),
                        ),
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddEditFavouriteSpotScreen(spot: spot),
                            ),
                          );
                          if (result == true) {
                            await _loadSpots();
                          }
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AddEditFavouriteSpotScreen(),
            ),
          );
          if (result == true) {
            await _loadSpots();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
