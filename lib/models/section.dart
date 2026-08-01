class Section {
  final int id;
  final int chapterId;
  final int order;
  final String title;
  final String content;

  const Section({
    required this.id,
    required this.chapterId,
    required this.order,
    required this.title,
    required this.content,
  });

  factory Section.fromJson(Map<String, dynamic> json) => Section(
        id: json['id'],
        chapterId: json['chapterId'],
        order: json['order'],
        title: json['title'],
        content: json['content'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'chapterId': chapterId,
        'order': order,
        'title': title,
        'content': content,
      };
}
