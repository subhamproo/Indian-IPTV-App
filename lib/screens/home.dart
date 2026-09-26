import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ip_tv/model/channel.dart';
import 'package:ip_tv/model/stream_source.dart';
import 'package:ip_tv/screens/player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../provider/channels_provider.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  State<Home> createState() => _Home();
}

class _Home extends State<Home>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {

  List<Channel> channels = [];
  List<Channel> filteredChannels = [];
  List<StreamSource> streamSources = [];
  StreamSource? selectedSource;
  List<Channel> _favourites = [];
  bool _showFavourites = false;
  bool _isLoadingDefaults = false;

  final ChannelsProvider channelsProvider = ChannelsProvider();
  bool _isLoading = true;

  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();
  final FocusNode _gridFocusNode = FocusNode();
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  static const String _spFavouritesKey = 'sp_favourites';
  static const String _spInitializedKey = 'sp_favs_initialized';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _initSpeech();
    _loadFavourites().then((_) => fetchStreamSources());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    searchController.dispose();
    searchFocusNode.dispose();
    _gridFocusNode.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WakelockPlus.enable();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      WakelockPlus.disable();
    }
  }

  Future<void> _loadFavourites() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_spFavouritesKey);
    if (json != null) {
      final list = jsonDecode(json) as List;
      if (mounted) {
        setState(() {
          _favourites = list
              .map((m) => _channelFromMap(m as Map<String, dynamic>))
              .toList();
        });
      }
    }
  }

  Future<void> _saveFavourites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _spFavouritesKey,
      jsonEncode(_favourites.map(_channelToMap).toList()),
    );
  }

  Future<void> _loadDefaultFavourite() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_spInitializedKey) == true) return;

    final indianSource = streamSources.firstWhere(
      (s) => s.name.toLowerCase().contains('indian'),
      orElse: () => StreamSource(name: '', streamUrl: ''),
    );
    if (indianSource.streamUrl.isEmpty) return;

    if (mounted) setState(() => _isLoadingDefaults = true);

    try {
      final tempProvider = ChannelsProvider();
      final data = await tempProvider.fetchM3UFile(indianSource.streamUrl);
      final sony = data.firstWhere(
        (c) => c.name.toLowerCase().contains('sony entertainment'),
        orElse: () => Channel(name: '', logoUrl: '', streamUrl: ''),
      );
      if (sony.name.isNotEmpty && mounted) {
        setState(() {
          if (!_favourites.any((f) => f.streamUrl == sony.streamUrl)) {
            _favourites.insert(0, sony);
          }
        });
        await _saveFavourites();
        await prefs.setBool(_spInitializedKey, true);
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoadingDefaults = false);
  }

  Channel _channelFromMap(Map<String, dynamic> m) => Channel(
        name: m['name'] as String,
        logoUrl: m['logoUrl'] as String,
        streamUrl: m['streamUrl'] as String,
      );

  Map<String, dynamic> _channelToMap(Channel c) =>
      {'name': c.name, 'logoUrl': c.logoUrl, 'streamUrl': c.streamUrl};

  void _addToFavourites(Channel channel) {
    if (_favourites.any((f) => f.streamUrl == channel.streamUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${channel.name} is already in Favourites')),
      );
      return;
    }
    setState(() => _favourites.add(channel));
    _saveFavourites();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅  Saved to Favourites')),
    );
  }

  void _removeFromFavourites(Channel channel) {
    setState(() =>
        _favourites.removeWhere((f) => f.streamUrl == channel.streamUrl));
    _saveFavourites();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Removed from Favourites')),
    );
  }

  void _showSaveToFavouritesDialog(Channel channel) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save to Favourites?'),
        content: Text(
          channel.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.star),
            label: const Text('Save'),
            onPressed: () {
              Navigator.pop(ctx);
              _addToFavourites(channel);
            },
          ),
        ],
      ),
    );
  }

  void _showRemoveFromFavouritesDialog(Channel channel) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from Favourites?'),
        content: Text(channel.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _removeFromFavourites(channel);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade400),
            child: const Text('Remove',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onError: (e) {
        if (mounted) setState(() => _isListening = false);
      },
      onStatus: (s) {
        if (s == SpeechToText.doneStatus ||
            s == SpeechToText.notListeningStatus) {
          if (mounted) setState(() => _isListening = false);
        }
      },
    );
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) return;
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: _onSpeechResult,
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 2),
        partialResults: true,
        localeId: 'en_IN',
        cancelOnError: true,
        listenMode: ListenMode.search,
      ),
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (mounted) setState(() => _isListening = false);
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords.trim();
    searchController.text = words;
    searchController.selection =
        TextSelection.fromPosition(TextPosition(offset: words.length));
    _filterChannels(words);
    if (result.finalResult) {
      _stopListening();
      searchFocusNode.unfocus();
    }
  }

  void _filterChannels(String query) {
    final result = channelsProvider.filterChannels(query);
    if (mounted) setState(() => filteredChannels = result);
  }

  Future<void> fetchStreamSources() async {
    try {
      final sources = await channelsProvider.fetchStreamSources();
      setState(() {
        streamSources = sources;
        _isLoading = false;
      });
      _loadDefaultFavourite();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('There was a problem loading stream categories')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> fetchChannels(StreamSource source) async {
    setState(() {
      _isLoading = true;
      selectedSource = source;
      _showFavourites = false;
      searchController.clear();
    });
    _stopListening();
    try {
      final data = await channelsProvider.fetchM3UFile(source.streamUrl);
      setState(() {
        channels = data;
        filteredChannels = data;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('There was a problem loading channels')),
        );
      }
      setState(() {
        selectedSource = null;
        _isLoading = false;
      });
    }
  }

  void backToCategories() {
    _stopListening();
    searchController.clear();
    setState(() {
      selectedSource = null;
      _showFavourites = false;
      channels = [];
      filteredChannels = [];
    });
  }

  void _openChannel(Channel channel) {
    Navigator.push(
      context,
      CupertinoPageRoute(builder: (_) => Player(url: channel.streamUrl)),
    );
  }

  @override
  Widget build(BuildContext context) {
    String title = 'Live TV';
    if (_showFavourites) title = '⭐  Favourites';
    if (selectedSource != null) title = selectedSource!.name;

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: (_showFavourites || selectedSource != null)
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: backToCategories,
                )
              : null,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _showFavourites
                ? _buildFavouritesGrid()
                : selectedSource == null
                    ? _buildCategoryGrid()
                    : _buildChannelGrid(),
      ),
    );
  }

  Widget _buildCategoryGrid() {
    final indianSource = streamSources.firstWhere(
      (s) => s.name.toLowerCase().contains('indian'),
      orElse: () => StreamSource(name: 'Indian TV', streamUrl: ''),
    );
    final sportsSource = streamSources.firstWhere(
      (s) => s.name.toLowerCase().contains('sport'),
      orElse: () => StreamSource(name: 'Sports', streamUrl: ''),
    );

    final items = [
      _CategoryItem(Icons.star, 'Favourites', Colors.amber.shade700),
      _CategoryItem(Icons.tv, indianSource.name, Colors.indigo.shade500),
      _CategoryItem(Icons.sports_cricket, sportsSource.name, Colors.teal.shade600),
    ];

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.4,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
      ),
      itemCount: 3,
      itemBuilder: (ctx, i) {
        final item = items[i];
        return Focus(
          autofocus: i == 0,
          child: Builder(builder: (ctx2) {
            final focused = Focus.of(ctx2).hasFocus;
            return InkWell(
              onTap: () {
                if (i == 0) {
                  setState(() => _showFavourites = true);
                } else if (i == 1 && indianSource.streamUrl.isNotEmpty) {
                  fetchChannels(indianSource);
                } else if (i == 2 && sportsSource.streamUrl.isNotEmpty) {
                  fetchChannels(sportsSource);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: focused
                      ? item.color.withOpacity(0.12)
                      : Colors.grey.shade50,
                  border: Border.all(
                    color: focused ? item.color : Colors.grey.shade300,
                    width: focused ? 4 : 1.5,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.icon, color: item.color, size: 40),
                    const SizedBox(width: 16),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: focused ? item.color : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildFavouritesGrid() {
    if (_isLoadingDefaults && _favourites.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Setting up your favourites...',
                style: TextStyle(fontSize: 18)),
          ],
        ),
      );
    }

    if (_favourites.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_border, size: 72, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No favourites yet.\n\nOpen Indian TV or Sports,\nthen hold OK on any channel to save it here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 18),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
        ),
        children: _favourites.asMap().entries.map((entry) {
          return _buildChannelTile(
            entry.value,
            isFavourite: true,
            autoFocus: entry.key == 0,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildChannelGrid() {
    return Column(
      children: [
        Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowDown) {
              searchFocusNode.unfocus();
              _gridFocusNode.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: TextField(
              controller: searchController,
              focusNode: searchFocusNode,
              onChanged: _filterChannels,
              onSubmitted: (_) => searchFocusNode.unfocus(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search channels...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          searchController.clear();
                          _filterChannels('');
                        },
                      ),
                    IconButton(
                      icon: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? Colors.red : null,
                      ),
                      tooltip: _isListening ? 'Stop' : 'Voice search',
                      onPressed: _speechAvailable
                          ? (_isListening ? _stopListening : _startListening)
                          : null,
                    ),
                  ],
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
        Expanded(
          child: Focus(
            focusNode: _gridFocusNode,
            child: SingleChildScrollView(
              child: GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                ),
                children: filteredChannels
                    .map((ch) => _buildChannelTile(ch, isFavourite: false))
                    .toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChannelTile(Channel channel,
      {required bool isFavourite, bool autoFocus = false}) {
    return Focus(
      autofocus: autoFocus,
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            border: Border.all(
              color: focused ? Colors.amber.shade700 : Colors.transparent,
              width: 4,
            ),
            color: focused ? Colors.amber.shade700.withOpacity(0.10) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: InkWell(
            onTap: () => _openChannel(channel),
            onLongPress: isFavourite
                ? () => _showRemoveFromFavouritesDialog(channel)
                : () => _showSaveToFavouritesDialog(channel),
            child: Padding(
              padding: const EdgeInsets.all(1.0),
              child: Column(
                children: [
                  Image.network(
                    channel.logoUrl,
                    height: 150,
                    width: 150,
                    errorBuilder: (_, __, ___) => Image.asset(
                      'assets/images/tv-icon.png',
                      width: 150,
                      height: 150,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 8.0),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        channel.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: focused ? Colors.amber.shade900 : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _CategoryItem {
  final IconData icon;
  final String label;
  final Color color;
  const _CategoryItem(this.icon, this.label, this.color);
}
