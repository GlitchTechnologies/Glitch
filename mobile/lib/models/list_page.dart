class ListPage<T> {
  final List<T> items;
  final int? nextCursor;
  final int? total;

  const ListPage({required this.items, this.nextCursor, this.total});
}
