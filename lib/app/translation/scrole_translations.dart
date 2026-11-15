import 'package:get/get.dart';

import 'app_translation.dart';
import 'app_translation_additions.dart';

/// Composition of the historical translations and the translations added
/// for the current UI flows. Arabic is deliberately excluded at runtime.
const Map<String, Map<String, String>> _scutStickerTranslations = {
  'fr': {
    'scut_sticker_editor_title': 'Modifier ton Scut',
    'scut_sticker_editor_done': 'Terminer',
    'scut_sticker_add': 'Ajouter un sticker',
    'scut_sticker_delete': 'Supprimer le sticker',
    'scut_sticker_editor_hint': 'Déplace, agrandis ou fais pivoter tes stickers avec les doigts.',
    'scut_sticker_export_progress': 'Incrustation des stickers… @progress %',
    'scut_sticker_export_error_title': 'Export des stickers impossible',
    'scut_sticker_export_error_message': 'La vidéo originale est conservée. Vérifie l’espace disponible puis réessaie. Détail : @error',
    'scut_sticker_picker_title': 'Ajouter à ton Scut',
    'scut_sticker_tab_emojis': 'Émojis',
    'scut_sticker_tab_stickers': 'Stickers',
    'scut_sticker_category_pop': 'Pop',
    'scut_sticker_category_naruto': 'Naruto',
    'scut_sticker_category_one_piece': 'One Piece',
    'scut_sticker_category_anime': 'Anime',
    'scut_sticker_category_africa_comics': 'BD Afrique',
  },
  'en': {
    'scut_sticker_editor_title': 'Edit your Scut',
    'scut_sticker_editor_done': 'Done',
    'scut_sticker_add': 'Add a sticker',
    'scut_sticker_delete': 'Delete sticker',
    'scut_sticker_editor_hint': 'Move, resize or rotate your stickers with your fingers.',
    'scut_sticker_export_progress': 'Adding stickers to video… @progress%',
    'scut_sticker_export_error_title': 'Could not export stickers',
    'scut_sticker_export_error_message': 'Your original video is safe. Check available storage and try again. Details: @error',
    'scut_sticker_picker_title': 'Add to your Scut',
    'scut_sticker_tab_emojis': 'Emojis',
    'scut_sticker_tab_stickers': 'Stickers',
    'scut_sticker_category_pop': 'Pop',
    'scut_sticker_category_naruto': 'Naruto',
    'scut_sticker_category_one_piece': 'One Piece',
    'scut_sticker_category_anime': 'Anime',
    'scut_sticker_category_africa_comics': 'African comics',
  },
  'es': {
    'scut_sticker_editor_title': 'Editar tu Scut',
    'scut_sticker_editor_done': 'Terminar',
    'scut_sticker_add': 'Añadir un sticker',
    'scut_sticker_delete': 'Eliminar sticker',
    'scut_sticker_editor_hint': 'Mueve, amplía o gira tus stickers con los dedos.',
    'scut_sticker_export_progress': 'Añadiendo stickers al vídeo… @progress%',
    'scut_sticker_export_error_title': 'No se pudieron exportar los stickers',
    'scut_sticker_export_error_message': 'Tu vídeo original se conserva. Comprueba el espacio disponible e inténtalo de nuevo. Detalle: @error',
    'scut_sticker_picker_title': 'Añadir a tu Scut',
    'scut_sticker_tab_emojis': 'Emojis',
    'scut_sticker_tab_stickers': 'Stickers',
    'scut_sticker_category_pop': 'Pop',
    'scut_sticker_category_naruto': 'Naruto',
    'scut_sticker_category_one_piece': 'One Piece',
    'scut_sticker_category_anime': 'Anime',
    'scut_sticker_category_africa_comics': 'Cómics africanos',
  },
  'de': {
    'scut_sticker_editor_title': 'Deinen Scut bearbeiten',
    'scut_sticker_editor_done': 'Fertig',
    'scut_sticker_add': 'Sticker hinzufügen',
    'scut_sticker_delete': 'Sticker löschen',
    'scut_sticker_editor_hint': 'Verschiebe, vergrößere oder drehe deine Sticker mit den Fingern.',
    'scut_sticker_export_progress': 'Sticker werden ins Video eingefügt… @progress%',
    'scut_sticker_export_error_title': 'Sticker konnten nicht exportiert werden',
    'scut_sticker_export_error_message': 'Dein Originalvideo bleibt erhalten. Prüfe den verfügbaren Speicherplatz und versuche es erneut. Details: @error',
    'scut_sticker_picker_title': 'Zu deinem Scut hinzufügen',
    'scut_sticker_tab_emojis': 'Emojis',
    'scut_sticker_tab_stickers': 'Sticker',
    'scut_sticker_category_pop': 'Pop',
    'scut_sticker_category_naruto': 'Naruto',
    'scut_sticker_category_one_piece': 'One Piece',
    'scut_sticker_category_anime': 'Anime',
    'scut_sticker_category_africa_comics': 'Afrikanische Comics',
  },
  'it': {
    'scut_sticker_editor_title': 'Modifica il tuo Scut',
    'scut_sticker_editor_done': 'Fine',
    'scut_sticker_add': 'Aggiungi uno sticker',
    'scut_sticker_delete': 'Elimina sticker',
    'scut_sticker_editor_hint': 'Sposta, ingrandisci o ruota gli sticker con le dita.',
    'scut_sticker_export_progress': 'Applicazione degli sticker al video… @progress%',
    'scut_sticker_export_error_title': 'Impossibile esportare gli sticker',
    'scut_sticker_export_error_message': 'Il video originale è conservato. Controlla lo spazio disponibile e riprova. Dettagli: @error',
    'scut_sticker_picker_title': 'Aggiungi al tuo Scut',
    'scut_sticker_tab_emojis': 'Emoji',
    'scut_sticker_tab_stickers': 'Sticker',
    'scut_sticker_category_pop': 'Pop',
    'scut_sticker_category_naruto': 'Naruto',
    'scut_sticker_category_one_piece': 'One Piece',
    'scut_sticker_category_anime': 'Anime',
    'scut_sticker_category_africa_comics': 'Fumetti africani',
  },
  'pt': {
    'scut_sticker_editor_title': 'Editar seu Scut',
    'scut_sticker_editor_done': 'Concluir',
    'scut_sticker_add': 'Adicionar figurinha',
    'scut_sticker_delete': 'Excluir figurinha',
    'scut_sticker_editor_hint': 'Mova, aumente ou gire suas figurinhas com os dedos.',
    'scut_sticker_export_progress': 'Aplicando figurinhas ao vídeo… @progress%',
    'scut_sticker_export_error_title': 'Não foi possível exportar as figurinhas',
    'scut_sticker_export_error_message': 'Seu vídeo original foi preservado. Verifique o espaço disponível e tente novamente. Detalhes: @error',
    'scut_sticker_picker_title': 'Adicionar ao seu Scut',
    'scut_sticker_tab_emojis': 'Emojis',
    'scut_sticker_tab_stickers': 'Figurinhas',
    'scut_sticker_category_pop': 'Pop',
    'scut_sticker_category_naruto': 'Naruto',
    'scut_sticker_category_one_piece': 'One Piece',
    'scut_sticker_category_anime': 'Anime',
    'scut_sticker_category_africa_comics': 'Quadrinhos africanos',
  },
  'zh': {
    'scut_sticker_editor_title': '编辑你的 Scut',
    'scut_sticker_editor_done': '完成',
    'scut_sticker_add': '添加贴纸',
    'scut_sticker_delete': '删除贴纸',
    'scut_sticker_editor_hint': '用手指移动、放大或旋转贴纸。',
    'scut_sticker_export_progress': '正在将贴纸合成到视频… @progress%',
    'scut_sticker_export_error_title': '贴纸导出失败',
    'scut_sticker_export_error_message': '原始视频已保留。请检查可用存储空间后重试。详情：@error',
    'scut_sticker_picker_title': '添加到你的 Scut',
    'scut_sticker_tab_emojis': '表情符号',
    'scut_sticker_tab_stickers': '贴纸',
    'scut_sticker_category_pop': '流行',
    'scut_sticker_category_naruto': '火影忍者',
    'scut_sticker_category_one_piece': '海贼王',
    'scut_sticker_category_anime': '动漫',
    'scut_sticker_category_africa_comics': '非洲漫画',
  },
  'ja': {
    'scut_sticker_editor_title': 'Scutを編集',
    'scut_sticker_editor_done': '完了',
    'scut_sticker_add': 'ステッカーを追加',
    'scut_sticker_delete': 'ステッカーを削除',
    'scut_sticker_editor_hint': '指でステッカーを移動、拡大、回転できます。',
    'scut_sticker_export_progress': '動画にステッカーを合成中… @progress%',
    'scut_sticker_export_error_title': 'ステッカーをエクスポートできませんでした',
    'scut_sticker_export_error_message': '元の動画は保持されています。空き容量を確認して、もう一度お試しください。詳細：@error',
    'scut_sticker_picker_title': 'Scutに追加',
    'scut_sticker_tab_emojis': '絵文字',
    'scut_sticker_tab_stickers': 'ステッカー',
    'scut_sticker_category_pop': 'ポップ',
    'scut_sticker_category_naruto': 'ナルト',
    'scut_sticker_category_one_piece': 'ワンピース',
    'scut_sticker_category_anime': 'アニメ',
    'scut_sticker_category_africa_comics': 'アフリカの漫画',
  },
  'ru': {
    'scut_sticker_editor_title': 'Редактировать Scut',
    'scut_sticker_editor_done': 'Готово',
    'scut_sticker_add': 'Добавить стикер',
    'scut_sticker_delete': 'Удалить стикер',
    'scut_sticker_editor_hint': 'Перемещайте, увеличивайте и поворачивайте стикеры пальцами.',
    'scut_sticker_export_progress': 'Добавление стикеров в видео… @progress%',
    'scut_sticker_export_error_title': 'Не удалось экспортировать стикеры',
    'scut_sticker_export_error_message': 'Исходное видео сохранено. Проверьте свободное место и попробуйте снова. Подробности: @error',
    'scut_sticker_picker_title': 'Добавить в Scut',
    'scut_sticker_tab_emojis': 'Эмодзи',
    'scut_sticker_tab_stickers': 'Стикеры',
    'scut_sticker_category_pop': 'Поп',
    'scut_sticker_category_naruto': 'Наруто',
    'scut_sticker_category_one_piece': 'Ван-Пис',
    'scut_sticker_category_anime': 'Аниме',
    'scut_sticker_category_africa_comics': 'Африканские комиксы',
  },
};

class ScroleTranslations extends Translations {
  static Map<String, Map<String, String>>? _cachedKeys;

  @override
  Map<String, Map<String, String>> get keys {
    if (_cachedKeys != null) return _cachedKeys!;

    final merged = <String, Map<String, String>>{};
    final base = AppTranslations().keys;

    for (final entry in base.entries) {
      if (entry.key == 'ar') continue;
      merged[entry.key] = Map<String, String>.from(entry.value);
    }

    for (final entry in AppTranslationAdditions.keys.entries) {
      merged.putIfAbsent(entry.key, () => <String, String>{});
      merged[entry.key]!.addAll(entry.value);
    }

    for (final entry in _scutStickerTranslations.entries) {
      merged.putIfAbsent(entry.key, () => <String, String>{});
      merged[entry.key]!.addAll(entry.value);
    }

    _cachedKeys = merged;
    return _cachedKeys!;
  }
}
