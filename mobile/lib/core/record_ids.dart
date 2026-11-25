const int kIdEpochMs = 1767225600000;
const int kIdOffset = 1000000000000000;
const int kIdLowBits = 11;

DateTime createdAtOfId(int id) =>
    DateTime.fromMillisecondsSinceEpoch(kIdEpochMs + ((id - kIdOffset) >> kIdLowBits), isUtc: true).toLocal();
