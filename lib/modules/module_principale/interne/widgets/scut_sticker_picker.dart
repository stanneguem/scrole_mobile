import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Sélecteur commun d'emojis et de stickers intégrés pour la création de Scut.
class ScutStickerPicker {
  static const List<String> emojis = [
    '😂','🤣','🥹','😭','😍','🥰','😘','😎','🤩','🥳','😜','🤪',
    '😱','🤯','😴','🤔','🙄','😇','🤗','🫶','🫡','🤫','🤭','😈',
    '❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💖','💗','💓',
    '💞','💕','💘','💝','💟','❣️','💔','❤️‍🔥','💋','💌','💍','💎',
    '🔥','✨','⭐','🌟','💫','⚡','💥','🌈','☀️','🌙','☁️','❄️',
    '🌸','🌺','🌻','🌹','🍀','🌴','🦋','🐝','🐼','🐱','🐶','🦄',
    '🎉','🎊','🎈','🎁','🎀','🎵','🎶','🎧','🎤','🏆','🥇','👑',
    '🚀','✈️','🌍','📸','💯','🙌','👏','🤝','🙏','💪','🧿','🪩',
  ];

  /// Stickers typographiques et combos thématiques intégrés.
  /// Les références aux séries sont des créations textuelles originales,
  /// pas des illustrations ou logos officiels.
  static const Map<String, List<String>> stickerPacks = {
    'Pop': [
      'WOW!', 'OMG!', 'LOL', 'LOVE', 'XOXO', 'BEST DAY', 'GOOD VIBES',
      'ON FIRE', 'NO WAY', 'SO CUTE', 'HELLO!', 'BYE BYE', 'LET’S GO',
      'YAY!', 'MOOD', 'ICONIC', 'BLESSED', 'DREAM BIG', '100%',
      'SUPER!', 'AMAZING', 'HOT!', 'COOL', 'MISS YOU', '✨ WOW ✨',
      '💖 LOVE 💖', '🔥 HOT 🔥', '🌸 CUTE 🌸', '⭐ STAR ⭐',
      '💯 PERFECT', '🦋 FREE', '👑 QUEEN', '🚀 GO!', '🎉 PARTY',
      '🤍 PURE', '⚡ ENERGY', '🌈 HAPPY',
    ],
    'Naruto': [
      '🍥 NARUTO', '忍 NINJA', '火影 HOKAGE', '🍃 KONOHA',
      'CHAKRA MODE', 'RASENGAN', 'SHINOBI', 'AKATSUKI ☁️',
      'DATTEBAYO!', 'NINJA WAY', '九尾 KYŪBI', 'TEAM 7',
      '🌀 JUTSU!', 'SASUKE MODE', 'BELIEVE IT!',
    ],
    'One Piece': [
      '☠️ ONE PIECE', '🏴‍☠️ NAKAMA', '海賊 PIRATE', 'GEAR 5',
      'KING OF PIRATES', 'GRAND LINE', 'WANTED!', 'DEVIL FRUIT',
      'ゴムゴム GOMU', 'THOUSAND SUNNY', '👒 LUFFY VIBE',
      'ZORO MODE', 'NAMI LOVE', 'SANJI KICK', '海賊王',
    ],
    'Anime': [
      '⚔️ DEMON SLAYER', '領域展開', 'JUJUTSU MODE', 'PLUS ULTRA!',
      '🐉 DRAGON BALL', 'KAMEHAMEHA!', 'BANKAI!', 'BLEACH SOUL',
      '進撃 ATTACK!', 'SPY FAMILY', 'MY HERO', 'ANIME ADDICT',
      'OTAKU LIFE', 'SENPAI!', 'MANGA TIME', '✨ ANIME VIBES',
      '🔥 POWER UP', 'LEVEL UP!', 'PROTAGONIST',
    ],
    'BD Afrique': [
      '🇨🇲 TÉTU', '🕶️ HACKER', 'ÉBÈNE DUTA', 'KAMER BOY',
      'TUMBU', 'OKADA', 'ZEBRA COMICS', 'WAANDA COMICS',
      'AKOMA MBA', 'AYA DE YOPOUGON', 'AKISSI', 'GOORGOORLOU',
      'KWEZI', 'DJELIYA', 'AFRO COMICS', 'MADE IN AFRICA',
      '🇨🇲 MBOA VIBES', 'AFRO FUTURE', 'BULLE AFRICAINE',
      '9e ART AFRICAIN', 'TEAM CAMEROUN', 'NOS HISTOIRES',
    ],
  };

  static List<String> get stickers =>
      stickerPacks.values.expand((pack) => pack).toList();

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF171717),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => const _ScutStickerPickerSheet(),
    );
  }
}

class _ScutStickerPickerSheet extends StatefulWidget {
  const _ScutStickerPickerSheet();

  @override
  State<_ScutStickerPickerSheet> createState() => _ScutStickerPickerSheetState();
}

class _ScutStickerPickerSheetState extends State<_ScutStickerPickerSheet> {
  int _tab = 0;
  String _stickerCategory = 'Pop';

  static const Map<String, String> _categoryTranslationKeys = {
    'Pop': 'scut_sticker_category_pop',
    'Naruto': 'scut_sticker_category_naruto',
    'One Piece': 'scut_sticker_category_one_piece',
    'Anime': 'scut_sticker_category_anime',
    'BD Afrique': 'scut_sticker_category_africa_comics',
  };

  @override
  Widget build(BuildContext context) {
    final items = _tab == 0
        ? ScutStickerPicker.emojis
        : (ScutStickerPicker.stickerPacks[_stickerCategory] ?? const <String>[]);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .58,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Ajouter à ton Scut',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    _tabButton('scut_sticker_tab_emojis'.tr, 0, Icons.emoji_emotions_outlined),
                    _tabButton('scut_sticker_tab_stickers'.tr, 1, Icons.auto_awesome_outlined),
                  ],
                ),
              ),
              if (_tab == 1) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: ScutStickerPicker.stickerPacks.keys.map((category) {
                      final selected = _stickerCategory == category;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text((_categoryTranslationKeys[category] ?? category).tr),
                          selected: selected,
                          onSelected: (_) => setState(() => _stickerCategory = category),
                          backgroundColor: Colors.white.withValues(alpha: .06),
                          selectedColor: Colors.white.withValues(alpha: .2),
                          labelStyle: TextStyle(
                            color: Colors.white,
                            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                          ),
                          side: BorderSide.none,
                          showCheckmark: false,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Expanded(
                child: GridView.builder(
                  itemCount: items.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (_, index) {
                    final item = items[index];
                    final isEmoji = _tab == 0;
                    return Material(
                      color: Colors.white.withValues(alpha: .07),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(context, item),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                item,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isEmoji ? 34 : 17,
                                  fontWeight: FontWeight.w900,
                                  shadows: isEmoji
                                      ? null
                                      : const [
                                          Shadow(
                                            color: Colors.black54,
                                            blurRadius: 5,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabButton(String label, int index, IconData icon) {
    final selected = _tab == index;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () => setState(() => _tab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withValues(alpha: .14) : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
