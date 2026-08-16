import '../models/emotion.dart';

/// 一条本地情绪规则。
class EmotionRule {
  const EmotionRule({
    required this.name,
    required this.emotion,
    required this.keywords,
    required this.statusPhrase,
  });

  final String name;
  final Emotion emotion;
  final List<String> keywords;
  final String statusPhrase;
}

/// 本地规则映射表（13 个核心情绪），作为 PocketClaw / 云端 LLM 的兜底。
const List<EmotionRule> kLocalEmotionRules = [
  EmotionRule(
    name: '开心',
    emotion: Emotion(
      emoji: '😊',
      colorHex: '#FFD93D',
      vibration: [100, 80, 100, 80, 100],
      suggestion: '继续保持好心情',
    ),
    statusPhrase: '今天心情不错哦',
    keywords: [
      '开心', '高兴', '快乐', '幸福', '爽', '好心情', '哈哈', '棒', '喜欢',
      '美好', '满意', '太好了', '真不错',
    ],
  ),
  EmotionRule(
    name: '难过',
    emotion: Emotion(
      emoji: '😢',
      colorHex: '#64B5F6',
      vibration: [200, 120, 200],
      suggestion: '抱抱你，慢慢来',
    ),
    statusPhrase: '有点难过，我陪你',
    keywords: [
      '难过', '伤心', '哭', '委屈', '失落', '沮丧', '悲伤', '难受', '心碎',
      '郁闷', '不开心', '想哭',
    ],
  ),
  EmotionRule(
    name: '累了',
    emotion: Emotion(
      emoji: '😩',
      colorHex: '#90A4AE',
      vibration: [300, 150, 300],
      suggestion: '休息一下下',
    ),
    statusPhrase: '看起来需要休息了',
    keywords: ['累', '疲惫', '困', '乏力', '没力气', '好累', '熬夜', '睡眠'],
  ),
  EmotionRule(
    name: '生气',
    emotion: Emotion(
      emoji: '😤',
      colorHex: '#EF5350',
      vibration: [80, 60, 80, 60, 80],
      suggestion: '深呼吸，消消气',
    ),
    statusPhrase: '火气有点大哦',
    keywords: [
      '生气', '愤怒', '气死', '讨厌', '烦死', '火大', '恼火', '暴躁',
      '想骂人', '不公平',
    ],
  ),
  EmotionRule(
    name: '兴奋',
    emotion: Emotion(
      emoji: '🤩',
      colorHex: '#FF8A65',
      vibration: [80, 60, 80, 60, 120, 60],
      suggestion: '去分享这份快乐',
    ),
    statusPhrase: '好兴奋，能量满满',
    keywords: [
      '兴奋', '激动', '期待', '迫不及待', '太棒了', '厉害', '牛', '冲',
      '加油', '成功了',
    ],
  ),
  EmotionRule(
    name: '平静',
    emotion: Emotion(
      emoji: '😌',
      colorHex: '#81C784',
      vibration: [100, 100],
      suggestion: '享受此刻安宁',
    ),
    statusPhrase: '内心很平静',
    keywords: ['平静', '安静', '放松', '舒服', '自在', '淡定', '平和', '惬意'],
  ),
  EmotionRule(
    name: '困惑',
    emotion: Emotion(
      emoji: '🤔',
      colorHex: '#BA68C8',
      vibration: [120, 100, 120, 100, 120],
      suggestion: '问题拆开看',
    ),
    statusPhrase: '好像有点想不通',
    keywords: [
      '困惑', '不懂', '为什么', '不明白', '纠结', '犹豫', '迷茫', '不知道',
      '怎么办', '搞不懂',
    ],
  ),
  EmotionRule(
    name: '害怕',
    emotion: Emotion(
      emoji: '😨',
      colorHex: '#7986CB',
      vibration: [60, 40, 60, 40, 160],
      suggestion: '我在你身边',
    ),
    statusPhrase: '别怕，我在呢',
    keywords: [
      '害怕', '恐惧', '吓', '担心', '不安', '忐忑', '慌张', '惊', '怕死',
    ],
  ),
  EmotionRule(
    name: '惊喜',
    emotion: Emotion(
      emoji: '🤗',
      colorHex: '#4DB6AC',
      vibration: [60, 50, 60, 50, 200],
      suggestion: '把美好记下来',
    ),
    statusPhrase: '哇，有惊喜的感觉',
    keywords: [
      '惊喜', '意外', '礼物', '没想到', '居然', '哇塞', '好消息', '中奖',
    ],
  ),
  EmotionRule(
    name: '焦虑',
    emotion: Emotion(
      emoji: '😨',
      colorHex: '#FFB74D',
      vibration: [90, 70, 90, 70, 90, 70],
      suggestion: '先做最小一步',
    ),
    statusPhrase: '有点焦虑，放轻松',
    keywords: [
      '焦虑', '着急', '来不及', '压力', '紧张', '烦躁', '赶不上', 'deadline',
      '截止', '考核', '面试',
    ],
  ),
  EmotionRule(
    name: '思念',
    emotion: Emotion(
      emoji: '😢',
      colorHex: '#4FC3F7',
      vibration: [180, 140, 180],
      suggestion: '发个消息问问',
    ),
    statusPhrase: '在想某个人吧',
    keywords: ['思念', '想念', '想你', '想家', '惦记', '好久不见', '怀念'],
  ),
  EmotionRule(
    name: '感激',
    emotion: Emotion(
      emoji: '🤗',
      colorHex: '#AED581',
      vibration: [100, 80, 100, 80, 200],
      suggestion: '把感谢说出来',
    ),
    statusPhrase: '心怀感激呢',
    keywords: ['感激', '感谢', '谢谢', '感恩', '多亏', '幸亏', '暖心', '帮助'],
  ),
  EmotionRule(
    name: '好奇',
    emotion: Emotion(
      emoji: '🤔',
      colorHex: '#9575CD',
      vibration: [110, 90, 110],
      suggestion: '大胆去探索吧',
    ),
    statusPhrase: '好奇心上线了',
    keywords: ['好奇', '想知道', '探索', '新鲜', '试试', '好玩', '兴趣'],
  ),
];

const Emotion _defaultEmotion = Emotion(
  emoji: '😊',
  colorHex: '#FFD93D',
  vibration: [100, 80, 100, 80, 100],
  suggestion: '我在听，说说吧',
);

/// 本地规则兜底：命中关键词最多的情绪胜出；无命中回退「开心」。
EmotionRule resolveLocalEmotion(String text) {
  var best = kLocalEmotionRules.first;
  var bestScore = -1;
  for (final rule in kLocalEmotionRules) {
    var score = 0;
    for (final keyword in rule.keywords) {
      if (text.contains(keyword)) score++;
    }
    if (score > bestScore) {
      best = rule;
      bestScore = score;
    }
  }
  if (bestScore <= 0) {
    return const EmotionRule(
      name: '开心',
      emotion: _defaultEmotion,
      keywords: [],
      statusPhrase: '我在认真听你说',
    );
  }
  return best;
}

/// 名称 → 规则。
EmotionRule emotionRuleByName(String name) => kLocalEmotionRules.firstWhere(
      (rule) => rule.name == name,
      orElse: () => const EmotionRule(
        name: '开心',
        emotion: _defaultEmotion,
        keywords: [],
        statusPhrase: '我在认真听你说',
      ),
    );
