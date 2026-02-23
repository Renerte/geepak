pub fn findLast(array: []const u8, element: u8) ?usize {
    var idx: ?usize = null;
    for (array, 0..) |el, i| {
        if (el == element) idx = i;
    }
    return idx;
}
