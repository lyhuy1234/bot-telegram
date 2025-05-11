import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

const String token = '7974300375:AAFXK-WR6YmTlKgXVhLHIfbjqLPbbjzlu9c';
const String baseUrl = 'https://api.telegram.org/bot$token';

Map<int, List<DateTime>> userAlarms = {};
Map<String, bool> canListen = {};
Map<int, String> alarmSongs = {};
List<int> adminUsers = [7585438801];
int ownerId = 7585438801;

List<DateTime> groupAlarms = [];
String? globalAlarmSong;
Map<String, int> usernameToId = {};
List<int> groupMemberIds = [];

void main() async {
  print('Bot started...');
  int offset = 0;

  Timer.periodic(Duration(seconds: 30), (_) {
    checkAlarms();
  });

  while (true) {
    final updates = await getUpdates(offset);
    for (final update in updates) {
      offset = update['update_id'] + 1;
      handleUpdate(update);
    }
  }
}

Future<List<dynamic>> getUpdates(int offset) async {
  final String url = '$baseUrl/getUpdates?offset=$offset';
  final response = await http.get(Uri.parse(url));
  if (response.statusCode == 200) {
    final json = jsonDecode(response.body);
    return json['result'];
  } else {
    print('Error: ${response.statusCode}');
  }
  return [];
}

Future<bool> isGroupOwner(int chatId, int userId) async {
  final String url = '$baseUrl/getChatAdministrators?chat_id=$chatId';
  final response = await http.get(Uri.parse(url));

  if (response.statusCode == 200) {
    final json = jsonDecode(response.body);
    final admins = json['result'];
    return admins.isNotEmpty && admins[0]['user']['id'] == userId;
  } else {
    print('Error: ${response.statusCode}');
  }
  return false;
}

Future<void> getGroupMembers(int chatId) async {
  groupMemberIds.clear();
  final String url = '$baseUrl/getChatMembersCount?chat_id=$chatId';
  final response = await http.get(Uri.parse(url));
  if (response.statusCode == 200) {
    final json = jsonDecode(response.body);
    final memberCount = json['result'];
    for (int i = 0; i < memberCount; i += 100) {
      final membersUrl = '$baseUrl/getChatMembers?chat_id=$chatId&offset=$i&limit=100';
      final membersResponse = await http.get(Uri.parse(membersUrl));
      if (membersResponse.statusCode == 200) {
        final membersJson = jsonDecode(membersResponse.body);
        for (var member in membersJson['result']) {
          groupMemberIds.add(member['user']['id']);
        }
      }
    }
  }
}

void handleUpdate(Map update) async {
  final message = update['message'];
  if (message == null) return;

  final userId = message['from']['id'];
  final chatId = message['chat']['id'];
  final text = message['text'] ?? '';
  final username = message['from']['username'] ?? '';

  if (username.isNotEmpty) {
    usernameToId[username] = userId;
  }

  if (text.startsWith('/start')) {
    sendMessage(chatId, 'Welcome to the Clock Alarm Bot!');
  } else if (text.startsWith('/setalarm')) {
    if (message['chat']['type'] == 'group' || message['chat']['type'] == 'supergroup') {
      if (isAdmin(userId) || await isGroupOwner(chatId, userId)) {
        final timeParts = text.split(' ');
        if (timeParts.length >= 2) {
          try {
            final alarmTime = parseTimeToDateTime(timeParts.sublist(1).join(' '));
            groupAlarms.add(alarmTime);
            await getGroupMembers(chatId);
            for (final memberId in groupMemberIds) {
              final usernameEntry = usernameToId.entries.firstWhere(
                  (entry) => entry.value == memberId,
                  orElse: () => MapEntry('', 0));
              if (canListen[usernameEntry.key] == true) {
                if (globalAlarmSong != null) {
                  await sendAudio(memberId, globalAlarmSong!,
                      '⏰ Alarm set for group at ${alarmTime.hour}:${alarmTime.minute.toString().padLeft(2, '0')}!');
                } else {
                  sendMessage(memberId,
                      '⏰ Alarm set for group at ${alarmTime.hour}:${alarmTime.minute.toString().padLeft(2, '0')}!');
                }
              }
            }
            sendMessage(chatId, 'Alarm set for $alarmTime and all group members have been notified.');
          } catch (e) {
            sendMessage(chatId, 'Invalid format. Use: /setalarm HH:mm AM/PM');
          }
        } else {
          sendMessage(chatId, 'Usage: /setalarm HH:mm AM/PM');
        }
      } else {
        sendMessage(chatId, 'Only group admins or the owner can set group alarms.');
      }
    } else {
      final timeParts = text.split(' ');
      if (timeParts.length >= 2) {
        try {
          final alarmTime = parseTimeToDateTime(timeParts.sublist(1).join(' '));
          userAlarms.putIfAbsent(userId, () => []).add(alarmTime);
          sendMessage(chatId, 'Alarm set for $alarmTime');
        } catch (e) {
          sendMessage(chatId, 'Invalid format. Use: /setalarm HH:mm AM/PM');
        }
      } else {
        sendMessage(chatId, 'Usage: /setalarm HH:mm AM/PM');
      }
    }
  } else if (text.startsWith('/setgroupalarm')) {
    if (isAdmin(userId) || await isGroupOwner(chatId, userId)) {
      final parts = text.split(' ');
      if (parts.length >= 2) {
        try {
          final alarmTime = parseTimeToDateTime(parts.sublist(1).join(' '));
          groupAlarms.add(alarmTime);
          await getGroupMembers(chatId);
          for (final memberId in groupMemberIds) {
            final usernameEntry = usernameToId.entries.firstWhere(
                (entry) => entry.value == memberId,
                orElse: () => MapEntry('', 0));
            if (canListen[usernameEntry.key] == true) {
              if (globalAlarmSong != null) {
                await sendAudio(memberId, globalAlarmSong!,
                    '⏰ Group Alarm ringing at ${alarmTime.hour}:${alarmTime.minute.toString().padLeft(2, '0')}!');
              } else {
                sendMessage(memberId,
                    '⏰ Group alarm ringing at ${alarmTime.hour}:${alarmTime.minute.toString().padLeft(2, '0')}!');
              }
            }
          }
          sendMessage(chatId, 'Group alarm set for $alarmTime');
        } catch (e) {
          sendMessage(chatId, 'Invalid format. Use: /setgroupalarm HH:mm AM/PM');
        }
      } else {
        sendMessage(chatId, 'Usage: /setgroupalarm HH:mm AM/PM');
      }
    } else {
      sendMessage(chatId, 'Only admins or the owner can set group alarms.');
    }
  } else if (text.startsWith('/allowlisten')) {
    if (isAdmin(userId) || await isGroupOwner(chatId, userId)) {
      final parts = text.split(' ');
      if (parts.length == 2) {
        final targetUsername = parts[1];
        if (targetUsername.isNotEmpty) {
          canListen[targetUsername] = true;
          sendMessage(chatId, 'User @$targetUsername can now hear alarms.');
        }
      }
    } else {
      sendMessage(chatId, 'Only admins or the owner can allow users to hear alarms.');
    }
  } else if (text.startsWith('/denylisten')) {
    if (isAdmin(userId) || await isGroupOwner(chatId, userId)) {
      final parts = text.split(' ');
      if (parts.length == 2) {
        final targetUsername = parts[1];
        if (targetUsername.isNotEmpty) {
          canListen[targetUsername] = false;
          sendMessage(chatId, 'User @$targetUsername can’t hear alarms now.');
        }
      }
    } else {
      sendMessage(chatId, 'Only admins or the owner can deny users from hearing alarms.');
    }
  }
}

void sendMessage(int chatId, String text) async {
  final String url = '$baseUrl/sendMessage';
  await http.post(
    Uri.parse(url),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'chat_id': chatId, 'text': text}),
  );
}

Future<void> sendAudio(int chatId, String audioFileId, String caption) async {
  final String url = '$baseUrl/sendAudio';
  await http.post(
    Uri.parse(url),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'chat_id': chatId,
      'audio': audioFileId,
      'caption': caption,
    }),
  );
}

void checkAlarms() async {
  final now = DateTime.now();

  userAlarms.forEach((userId, alarmList) async {
    final dueAlarms = alarmList.where((alarmTime) => now.isAfter(alarmTime)).toList();
    for (var alarmTime in dueAlarms) {
      alarmList.remove(alarmTime);
      final songId = alarmSongs[userId];
      if (songId != null) {
        await sendAudio(userId, songId, 'Alarm ringing at ${alarmTime.hour}:${alarmTime.minute.toString().padLeft(2, '0')}!');
      } else {
        sendMessage(userId, 'Alarm ringing at ${alarmTime.hour}:${alarmTime.minute.toString().padLeft(2, '0')}!');
      }
    }
  });

  final dueGroupAlarms = groupAlarms.where((t) => now.isAfter(t)).toList();
  for (var alarmTime in dueGroupAlarms) {
    groupAlarms.remove(alarmTime);
    for (final username in canListen.keys) {
      if (canListen[username] == true) {
        final userId = usernameToId[username];
        if (userId != null) {
          if (globalAlarmSong != null) {
            await sendAudio(userId, globalAlarmSong!, '⏰ Group Alarm ringing at ${alarmTime.hour}:${alarmTime.minute.toString().padLeft(2, '0')}!');
          } else {
            sendMessage(userId, '⏰ Group alarm ringing at ${alarmTime.hour}:${alarmTime.minute.toString().padLeft(2, '0')}!');
          }
        }
      }
    }
  }
}

bool isAdmin(int userId) {
  return adminUsers.contains(userId);
}

DateTime parseTimeToDateTime(String timeString) {
  final now = DateTime.now();
  final match = RegExp(r'^(\d{1,2}):(\d{2})\s?(AM|PM)?$', caseSensitive: false).firstMatch(timeString.trim());

  if (match != null) {
    int hour = int.parse(match.group(1)!);
    int minute = int.parse(match.group(2)!);
    final period = match.group(3)?.toUpperCase();

    if (hour < 1 || hour > 12 || minute < 0 || minute > 59) {
      throw FormatException('Invalid time values');
    }

    if (period != null) {
      if (period == 'AM' && hour == 12) {
        hour = 0;
      } else if (period == 'PM' && hour != 12) {
        hour += 12;
      }
    }

    var alarmTime = DateTime(now.year, now.month, now.day, hour, minute);
    if (alarmTime.isBefore(now)) {
      alarmTime = alarmTime.add(Duration(days: 1));
    }
    return alarmTime;
  } else {
    throw FormatException('Invalid time format');
  }
}
