import 'package:flutter_test/flutter_test.dart';
import 'package:wordbook/core/word_text.dart';
import 'package:wordbook/data/word_draft.dart';
import 'package:wordbook/services/llm_json.dart';
import 'package:wordbook/services/local_word_parser.dart';

void main() {
  group('WordText 清洗', () {
    test('去掉题号与标点', () {
      expect(WordText.cleanWord('1. abandon'), 'abandon');
      expect(WordText.cleanWord('(2) give up'), 'give up');
      expect(WordText.cleanWord('“apple”'), 'apple');
    });

    test('过滤中文与数字', () {
      expect(WordText.cleanWord('苹果'), '');
      expect(WordText.cleanWord('abc1'), '');
    });

    test('音标规范化', () {
      expect(WordText.cleanPhonetic('əˈbændən'), '/əˈbændən/');
      expect(WordText.cleanPhonetic(' /əˈbændən/ '), '/əˈbændən/');
      expect(WordText.cleanPhonetic('[əˈbændən]'), '/əˈbændən/');
      expect(WordText.cleanPhonetic('放弃'), '');
    });
  });

  group('大模型 JSON 容错解析', () {
    test('支持 markdown 代码块 + 尾逗号', () {
      const String raw = '```json\n[{"word":"apple","phonetic":"/ˈæpl/",'
          '"meaning":"n. 苹果",},]\n```';
      final List<WordDraft> drafts = LlmJsonParser.parse(raw);
      expect(drafts.length, 1);
      expect(drafts.first.word, 'apple');
      expect(drafts.first.phonetic, '/ˈæpl/');
    });

    test('支持 {words:[...]} 包装与字段别名', () {
      const String raw = '{"words":[{"english":"give up","pron":"/ɡɪv ʌp/",'
          '"translation":"放弃"}],"total":1}';
      final List<WordDraft> drafts = LlmJsonParser.parse(raw);
      expect(drafts.single.word, 'give up');
      expect(drafts.single.meaning, '放弃');
    });

    test('音标混在释义里也能拆出来', () {
      const String raw = '[{"word":"abandon","meaning":"放弃 /əˈbændən/"}]';
      final List<WordDraft> drafts = LlmJsonParser.parse(raw);
      expect(drafts.single.phonetic, '/əˈbændən/');
      expect(drafts.single.meaning, '放弃');
    });

    test('同名去重', () {
      const String raw = '[{"word":"apple","meaning":"苹果"},'
          '{"word":"Apple","meaning":"苹果公司"}]';
      expect(LlmJsonParser.parse(raw).length, 1);
    });
  });

  group('本地规则解析', () {
    test('常见词表排版', () {
      const String text = '1. abandon /əˈbændən/ v. 放弃\n'
          '2. ability [əˈbɪləti] n. 能力\n'
          '3. absent adj. 缺席的';
      final List<WordDraft> drafts = LocalWordParser.parse(text);
      expect(drafts.length, 3);
      expect(drafts[0].word, 'abandon');
      expect(drafts[0].phonetic, '/əˈbændən/');
      expect(drafts[0].meaning.contains('放弃'), isTrue);
      expect(drafts[1].word, 'ability');
      expect(drafts[2].word, 'absent');
    });

    test('竖排：单词独占一行，下一行是释义', () {
      const String text = 'abandon\n放弃；抛弃';
      final List<WordDraft> drafts = LocalWordParser.parse(text);
      expect(drafts.single.word, 'abandon');
      expect(drafts.single.meaning, '放弃；抛弃');
    });
  });
}
