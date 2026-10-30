// 临时冒烟脚本：验证纯 Dart 的解析逻辑（不依赖 Flutter 运行时）。
import 'package:wordbook/core/word_text.dart';
import 'package:wordbook/data/word_draft.dart';
import 'package:wordbook/services/llm_json.dart';
import 'package:wordbook/services/agent_service.dart';
import 'package:wordbook/services/local_word_parser.dart';

int failed = 0;

void check(String name, Object? actual, Object? expected) {
  final bool ok = actual == expected;
  if (!ok) {
    failed++;
    print('FAIL $name\n  expected: $expected\n  actual  : $actual');
  } else {
    print('ok   $name');
  }
}

void main() {
  check('cleanWord 1.', WordText.cleanWord('1. abandon'), 'abandon');
  check('cleanWord (2)', WordText.cleanWord('(2) give up'), 'give up');
  check('cleanWord quotes', WordText.cleanWord('“apple”'), 'apple');
  check('cleanWord cjk', WordText.cleanWord('苹果'), '');
  check('cleanWord digit', WordText.cleanWord('abc1'), '');
  check('phonetic plain', WordText.cleanPhonetic('əˈbændən'), '/əˈbændən/');
  check('phonetic []', WordText.cleanPhonetic('[əˈbændən]'), '/əˈbændən/');
  check('phonetic cjk', WordText.cleanPhonetic('放弃'), '');

  const String fenced = '```json\n[{"word":"apple","phonetic":"/ˈæpl/",'
      '"meaning":"n. 苹果",},]\n```';
  final List<WordDraft> a = LlmJsonParser.parse(fenced);
  check('llm fenced count', a.length, 1);
  check('llm fenced word', a.first.word, 'apple');
  check('llm fenced phonetic', a.first.phonetic, '/ˈæpl/');

  const String wrapped =
      '{"words":[{"english":"give up","pron":"/ɡɪv ʌp/","translation":"放弃"}],"total":1}';
  final List<WordDraft> b = LlmJsonParser.parse(wrapped);
  check('llm wrapped word', b.single.word, 'give up');
  check('llm wrapped meaning', b.single.meaning, '放弃');

  const String mixed = '[{"word":"abandon","meaning":"放弃 /əˈbændən/"}]';
  final WordDraft c = LlmJsonParser.parse(mixed).single;
  check('llm split phonetic', c.phonetic, '/əˈbændən/');
  check('llm split meaning', c.meaning, '放弃');

  const String dup =
      '[{"word":"apple","meaning":"苹果"},{"word":"Apple","meaning":"苹果公司"}]';
  check('llm dedupe', LlmJsonParser.parse(dup).length, 1);

  const String listText = '1. abandon /əˈbændən/ v. 放弃\n'
      '2. ability [əˈbɪləti] n. 能力\n'
      '3. absent adj. 缺席的';
  final List<WordDraft> d = LocalWordParser.parse(listText);
  check('local count', d.length, 3);
  check('local word0', d[0].word, 'abandon');
  check('local phonetic0', d[0].phonetic, '/əˈbændən/');
  check('local meaning0 has 放弃', d[0].meaning.contains('放弃'), true);
  check('local word1', d[1].word, 'ability');
  check('local word2', d[2].word, 'absent');

  final WordDraft e = LocalWordParser.parse('abandon\n放弃；抛弃').single;
  check('local vertical word', e.word, 'abandon');
  check('local vertical meaning', e.meaning, '放弃；抛弃');

  // ---- 智能体相关的纯逻辑 ----
  check('vision intent: 圈选', instructionNeedsVision('只提取我画圈的单词'), true);
  check('vision intent: 名词', instructionNeedsVision('只要名词'), false);

  final List<WordDraft> pool = <WordDraft>[
    WordDraft(word: 'ability', meaning: 'n. 能力'),
    WordDraft(word: 'abandon', meaning: 'v. 放弃'),
    WordDraft(word: 'absolute', meaning: 'adj. 绝对的'),
    WordDraft(word: 'apple', meaning: ''),
  ];
  check('本地粗筛: 名词', localInstructionFilter(pool, '只要名词').map((WordDraft d) => d.word).join(','), 'ability');
  check('本地粗筛: 带释义', localInstructionFilter(pool, '只保留带释义的').length, 3);
  check('本地粗筛: 前2个', localInstructionFilter(pool, '前 2 个').length, 2);
  check('本地粗筛: 空要求', localInstructionFilter(pool, '').length, 4);

  print(failed == 0 ? '\nALL PASS' : '\n$failed FAILED');
}
