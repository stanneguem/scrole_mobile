import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../modules/module_decouverte/centre/models/discover_models.dart';

class SearchRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<SearchResultItem>> searchAll(String query) async {
    try {
      debugPrint('[SearchRepository] calling search_all with query: "$query"');
      final response = await _client.rpc('search_all', params: {
        'p_query': query,
      });

      debugPrint('[SearchRepository] response type: ${response.runtimeType}, data: $response');

      if (response is List) {
        final rawList = response
            .map((item) => SearchResultItem.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();

        final seen = <String>{};
        final uniqueList = <SearchResultItem>[];
        for (final item in rawList) {
          final key = '${item.category}_${item.id}';
          if (seen.add(key)) {
            uniqueList.add(item);
          }
        }
        return uniqueList;
      }
      return [];
    } catch (e, stack) {
      debugPrint('[SearchRepository] error calling search_all: $e');
      debugPrintStack(stackTrace: stack);
      throw Exception(e.toString());
    }
  }
}
