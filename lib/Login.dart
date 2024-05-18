import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'Chat.dart';

class Login extends StatefulWidget {
  @override
  _LoginState createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final TextEditingController _usernameController = TextEditingController();
  Map<String, dynamic> roomData = {};

  @override
  void initState() {
    super.initState();
    loadRoomData();
  }

  Future<void> loadRoomData() async {
    String jsonString = await rootBundle.loadString('assets/rooms.json');
    var decodedData = json.decode(jsonString);
    setState(() {
      roomData = decodedData['Rooms'];
    });
  }

  void _selectRoom(String roomName) {
    if (_usernameController.text.isNotEmpty) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            Chat(roomName: roomName, username: _usernameController.text),
      ));
    }
  }

  void _showCategorySheet() {
    _showBottomSheet(context, roomData.keys.toList(), _selectCategory);
  }

  void _selectCategory(String category) {
    var categoryData = roomData[category];
    if (categoryData is Map) {
      List<String> subCategories = categoryData.keys.cast<String>().toList();
      _showBottomSheet(context, subCategories, (subCategory) {
        _handleSubCategory(category, subCategory);
      }, showBackButton: true, backSheetFunction: _showCategorySheet);
    } else if (categoryData is List) {
      _showBottomSheet(context, categoryData.cast<String>(), _selectRoom);
    }
  }

  void _handleSubCategory(String category, String subCategory) {
    var subCategoryData = roomData[category][subCategory];
    if (subCategoryData is List) {
      // If it's a list, show the rooms directly
      _showBottomSheet(context, subCategoryData.cast<String>(), _selectRoom,
          showBackButton: true,
          backSheetFunction: () => _selectCategory(category));
    } else if (subCategoryData is Map) {
      // If it's a map, show the nested categories
      List<String> nestedCategories =
          subCategoryData.keys.cast<String>().toList();
      _showBottomSheet(context, nestedCategories, (nestedCategory) {
        // This assumes that the nested category will lead to a list of rooms
        var rooms = subCategoryData[nestedCategory];
        if (rooms is List) {
          _showBottomSheet(context, rooms.cast<String>(), _selectRoom,
              showBackButton: true,
              backSheetFunction: () =>
                  _handleSubCategory(category, subCategory));
        }
      },
          showBackButton: true,
          backSheetFunction: () => _selectCategory(category));
    }
  }

  void _showBottomSheet(
    BuildContext context,
    List<String> items,
    Function(String) onSelect, {
    bool showBackButton = false,
    VoidCallback? backSheetFunction,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Column(
          children: [
            if (showBackButton)
              BackButton(
                onPressed: () {
                  Navigator.pop(context);
                  if (backSheetFunction != null) {
                    backSheetFunction();
                  }
                },
              ),
            Expanded(
              child: GridView.builder(
                padding: EdgeInsets.all(8), // Adds padding around the grid
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, // Number of columns
                  crossAxisSpacing: 10, // Horizontal space between cards
                  mainAxisSpacing: 10, // Vertical space between cards
                  childAspectRatio: 3, // Aspect ratio of the cards
                ),
                itemCount: items.length,
                itemBuilder: (BuildContext context, int index) {
                  return OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onSelect(items[index]);
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.blue), // Border color
                      padding: EdgeInsets.symmetric(
                          vertical: 15,
                          horizontal: 20), // Padding inside the button
                    ),
                    child: Text(
                      items[index],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16, // Font size
                        color: Colors.red, // Text color
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Choose a Chat Room'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(labelText: 'Enter your username'),
            ),
            ElevatedButton(
              onPressed: () => _showBottomSheet(
                  context, roomData.keys.toList(), _selectCategory),
              child: Text('Select Chat Room Category'),
            ),
          ],
        ),
      ),
    );
  }
}
