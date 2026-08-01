import 'dart:convert';
import 'package:flutter/services.dart';
import '../../models/chapter.dart';
import '../../models/question.dart';
import '../../models/section.dart';

class JsonLoader {
  static Future<List<Chapter>> loadChapters() async {
    final str = await rootBundle.loadString('assets/json/chapters.json');
    final List<dynamic> list = json.decode(str);
    return list.map((e) => Chapter.fromJson(e)).toList();
  }

  static Future<List<Question>> loadQuestions() async {
    final str = await rootBundle.loadString('assets/json/questions.json');
    final List<dynamic> list = json.decode(str);
    return list.map((e) => Question.fromJson(e)).toList();
  }

  static Future<List<Section>> loadSections() async {
    final str = await rootBundle.loadString('assets/json/sections.json');
    final List<dynamic> list = json.decode(str);
    return list.map((e) => Section.fromJson(e)).toList();
  }
}
