// 由 Unicode emoji-test.txt（15.1，只取 15.0 及以前的完全限定表情，不含肤色变体和组件）
// 和 CLDR 中英文注释（annotations + annotationsDerived，Unicode License v3）生成。
// 一行一个：表情、能否换肤色（1/0）、中文关键词（| 分隔）、英文关键词（小写，| 分隔）。
// 顺序是 Unicode 的官方排序，搜索结果同分时按它排。不要手改，用
// scripts/make-emoji-catalog.py 重新生成。

enum EmojiCatalogData {
    static let table = """
😀	0	嘿嘿|笑脸|脸|高兴	grinning face|cheerful|cheery|face|grin|grinning|happy|laugh|nice|smile|smiling|teeth
😃	0	哈哈|太棒了|开口笑|开口笑脸|笑脸|脸|高兴	grinning face with big eyes|awesome|big|eyes|face|grin|grinning|happy|mouth|open|smile|smiling|teeth|yay
😄	0	大笑|哈哈|开口而笑的脸|开心|笑|脸|露齿而笑|高兴	grinning face with smiling eyes|eye|eyes|face|grin|grinning|happy|laugh|lol|mouth|open|smile|smiling
😁	0	嘻嘻|笑脸|笑颜|脸|露齿而笑	beaming face with smiling eyes|beaming|eye|eyes|face|grin|grinning|happy|nice|smile|smiling|teeth
😆	0	斜眼笑|lol|咧嘴笑|哈哈|开心|眯眼|眯眼大笑|笑|脸|高兴	grinning squinting face|closed|eyes|face|grinning|haha|hahaha|happy|laugh|lol|mouth|open|rofl|smile|smiling|squinting
😅	0	苦笑|冷汗|出汗|开口冒冷汗的脸|汗|泄气|紧张|脸	grinning face with sweat|cold|dejected|excited|face|grinning|mouth|nervous|open|smile|smiling|stress|stressed|sweat
🤣	0	笑得满地打滚|lolol|乐翻了|哈哈|地板|太扯了|打滚|满地打滚的笑|笑|笑得流泪|脸|超扯	rolling on the floor laughing|crying|face|floor|funny|haha|happy|hehe|hilarious|joy|laugh|lmao|lol|rofl|roflmao|rolling|tear
😂	0	笑哭了|lol|喜极而泣|大笑|眼泪|笑|笑哭|脸	face with tears of joy|crying|face|feels|funny|haha|happy|hehe|hilarious|joy|laugh|lmao|lol|rofl|roflmao|tear
🙂	0	呵呵|开心|浅笑的脸|笑|脸	slightly smiling face|face|happy|slightly|smile|smiling
🙃	0	倒脸|好玩|好笑|脸|颠倒|颠倒的脸	upside-down face|face|hehe|smile|upside-down
🫠	0	融化|冷笑|哈哈|尴尬|微笑|消失|液体|溶解|热	melting face|disappear|dissolve|embarrassed|face|haha|heat|hot|liquid|lol|melt|melting|sarcasm|sarcastic
😉	0	眨眼|媚眼|撩拨|眨眼的脸|笑|脸	winking face|face|flirt|heartbreaker|sexy|slide|tease|wink|winking|winks
😊	0	羞涩微笑|害羞|微笑|满意|笑脸相迎|羞涩|脸|脸红	smiling face with smiling eyes|blush|eye|eyes|face|glad|satisfied|smile|smiling
😇	0	微笑天使|光环|天使|天真|幻想|微笑|脸|顶罩光环的笑脸	smiling face with halo|angel|angelic|angels|blessed|face|fairy|fairytale|fantasy|halo|happy|innocent|peaceful|smile|smiling|spirit|tale
🥰	0	喜笑颜开|三颗爱心的笑脸|心|我爱你|爱慕|相爱|笑脸|迷恋|陷入爱河	smiling face with hearts|3|adore|crush|face|heart|hearts|ily|love|romance|smile|smiling|you
😍	0	花痴|我爱你|爱|红心|脸	smiling face with heart-eyes|143|bae|eye|face|feels|heart-eyes|hearts|ily|kisses|love|romance|romantic|smile|xoxo
🤩	0	好崇拜哦|兴奋|咧嘴笑|满天星|满眼星|脸|追星族|露齿笑	star-struck|excited|eyes|face|grinning|smile|star|starry-eyed|wow
😘	0	飞吻|亲亲|想你|我爱你|眨眼|脸	face blowing a kiss|adorbs|bae|blowing|face|flirt|heart|ily|kiss|love|lover|miss|muah|romantic|smooch|xoxo|you
😗	0	亲亲|亲吻|吻|脸	kissing face|143|date|dating|face|flirt|ily|kiss|love|smooch|smooches|xoxo|you
☺️	0	微笑|呵呵|开心|放松|笑|脸	smiling face|face|happy|outlined|relaxed|smile|smiling
😚	0	羞涩亲亲|亲亲|吻|我爱你|羞涩|脸|闭眼|闭眼亲吻	kissing face with closed eyes|143|bae|blush|closed|date|dating|eye|eyes|face|flirt|ily|kisses|kissing|smooches|xoxo
😙	0	微笑亲亲|亲亲|吻|微笑|笑颜亲吻|脸	kissing face with smiling eyes|143|closed|date|dating|eye|eyes|face|flirt|ily|kiss|kisses|kissing|love|night|smile|smiling
🥲	0	含泪的笑脸|喜悦|喜极而泣|幸福|微笑|微笑的|感动|感动的|感恩的|感激|眼泪|笑中带泪|笑脸|自豪|苦中作乐|释怀的|骄傲的	smiling face with tear|face|glad|grateful|happy|joy|pain|proud|relieved|smile|smiley|smiling|tear|touched
😋	0	好吃|口水|哈喇子|津津有味|流口水|美味|脸	face savoring food|delicious|eat|face|food|full|hungry|savor|smile|smiling|tasty|um|yum|yummy
😛	0	吐舌|吐舌头的脸|太好了|脸|舌头|调皮	face with tongue|awesome|cool|face|nice|party|stuck-out|sweet|tongue
😜	0	单眼吐舌|单眼|古怪|吐舌|开玩笑|怪人|挤眉弄眼|脸	winking face with tongue|crazy|epic|eye|face|funny|joke|loopy|nutty|party|stuck-out|tongue|wacky|weirdo|wink|winking|yolo
🤪	0	滑稽|大小眼|大眼|小眼|滑稽的脸|疯狂的脸|疯眼|疯脸|脸	zany face|crazy|eye|eyes|face|goofy|large|small|zany
😝	0	眯眼吐舌|可怕|吐舌|尝|眯眼|眼睛|脸|都好|随便	squinting face with tongue|closed|eye|eyes|face|gross|horrible|omg|squinting|stuck-out|taste|tongue|whatever|yolo
🤑	0	发财|拜金|脸|见钱眼开|金钱至上|钱	money-mouth face|face|money|money-mouth|mouth|paid
🤗	0	抱抱|抱|拥抱|笑|脸	smiling face with open hands|face|hands|hug|hugging|open|smiling
🤭	0	不说|不可说|傻笑|吃吃傻笑|哎呀|意外|捂嘴而笑|猛然发现|秘密|脸	face with hand over mouth|face|giggle|giggling|hand|mouth|oops|realization|secret|shock|sudden|surprise|whoops
🫢	0	睁眼捂嘴|哇塞|哑口无言|害怕|尴尬|怀疑|惊奇|惊愕|惊讶|敬畏|震惊	face with open eyes and hand over mouth|amazement|awe|disbelief|embarrass|eyes|face|gasp|hand|mouth|omg|open|over|quiet|scared|shock|surprise
🫣	0	偷看|偷窥|凝视|害怕|害羞|尴尬|迷住	face with peeking eye|captivated|embarrass|eye|face|hide|hiding|peek|peeking|peep|scared|shy|stare
🤫	0	安静的脸|嘘|嘘声手势的脸|安静	shushing face|face|quiet|shh|shush|shushing
🤔	0	想一想|思考|想|想事情|脸	thinking face|chin|consider|face|hmm|ponder|pondering|thinking|wondering
🫡	0	致敬|军队|好|好的|收到|敬礼|是|阳光	saluting face|face|good|luck|ma’am|ok|respect|salute|saluting|sir|troops|yes
🤐	0	闭嘴|住嘴|嘴|封口|秘密|脸	zipper-mouth face|face|keep|mouth|quiet|secret|shut|zip|zipper|zipper-mouth
🤨	0	挑眉|不信任|不敢置信|不赞同|怀疑|氧起眉毛的脸|眉毛上挑的脸|脸	face with raised eyebrow|disapproval|disbelief|distrust|emoji|eyebrow|face|hmm|mild|raised|skeptic|skeptical|skepticism|surprise|what
😐	0	冷漠|无感|脸|表情空洞|面无表情	neutral face|awkward|blank|deadpan|expressionless|face|fine|jealous|meh|neutral|oh|shade|straight|unamused|unhappy|unimpressed|whatever
😑	0	无语|没有反应|绷着脸|脸|茫然|面无表情	expressionless face|awkward|dead|expressionless|face|fine|inexpressive|jealous|meh|not|oh|omg|straight|uh|unhappy|unimpressed|whatever
😶	0	沉默|嘴|安静|没嘴|秘密|脸	face without mouth|awkward|blank|expressionless|face|mouth|mouthless|mute|quiet|secret|silence|silent|speechless
🫥	0	虚线脸|内向|无所谓|沮丧|消失|隐形|隐藏	dotted line face|depressed|disappear|dotted|face|hidden|hide|introvert|invisible|line|meh|whatever|wtv
😶‍🌫️	0	迷茫	face in clouds|absentminded|clouds|face|fog|head
😏	0	得意|假笑|冷笑|得意的笑|脸|诡异地笑	smirking face|boss|dapper|face|flirt|homie|kidding|leer|shade|slick|sly|smirk|smug|snicker|suave|suspicious|swag
😒	0	不高兴|不屑|不服|不爽的脸|脸|郁闷|鄙视|随便啦	unamused face|...|bored|face|fine|jealous|jel|jelly|pissed|smh|ugh|uhh|unamused|unhappy|weird|whatever
🙄	0	翻白眼|不敢苟同|无语|白眼|脸|随便啦	face with rolling eyes|eyeroll|eyes|face|rolling|shade|ugh|whatever
😬	0	龇牙咧嘴|咬牙切齿|尴尬|牙医|脸|露齿|露齿而笑|鬼脸	grimacing face|awk|awkward|dentist|face|grimace|grimacing|grinning|smile|smiling
😮‍💨	0	呼气|叹息|叹气|吹气|呼气的脸|唉|无奈|松一口气|疲惫|笑脸|释然	face exhaling|blow|blowing|exhale|exhaling|exhausted|face|gasp|groan|relief|sigh|smiley|smoke|whisper|whistle
🤥	0	说谎|匹诺曹|脸|长鼻子|长鼻子脸	lying face|face|liar|lie|lying|pinocchio
🫨	0	颤抖|哇|地震|天啊|惊喜|惊慌|晕头转向|疯狂|脸|震动|震惊	shaking face|crazy|daze|earthquake|face|omg|panic|shaking|shock|surprise|vibrate|whoa|wow
😌	0	松了口气|如释重负|松口气|脸|蝉	relieved face|calm|face|peace|relief|relieved|zen
😔	0	沉思|失落|心事重重|忧虑|脸	pensive face|awful|bored|dejected|died|disappointed|face|losing|lost|pensive|sad|sucks
😪	0	困|哭|想睡|满脸睡容|疲惫|睡觉|瞌睡|脸	sleepy face|crying|face|good|night|sad|sleep|sleeping|sleepy|tired
🤤	0	流口水|口水|垂涎|垂涎三尺|流口水的脸|脸	drooling face|drooling|face
😴	0	睡着了|呼噜|小睡|想睡|打呼|晚安|睡容|睡觉|累|累了|脸	sleeping face|bed|bedtime|face|good|goodnight|nap|night|sleep|sleeping|tired|whatever|yawn|zzz
😷	0	感冒|医生|口罩|戴口罩|戴口罩的脸|生病|病菌|脸	face with medical mask|cold|dentist|dermatologist|doctor|dr|face|germs|mask|medical|medicine|sick
🤒	0	发烧|体温计|咬着体温计的脸|温度计|生病|脸|量体温	face with thermometer|face|ill|sick|thermometer
🤕	0	受伤|头绑绷带|打绷带|脸	face with head-bandage|bandage|face|head-bandage|hurt|injury|ouch
🤢	0	恶心|吐|呕|恶心作呕的脸|脸|脸绿了	nauseated face|face|gross|nasty|nauseated|sick|vomit
🤮	0	呕吐|不舒服|吐|呕吐的脸|生病|病容|病恹恹|脸	face vomiting|barf|ew|face|gross|puke|sick|spew|throw|up|vomit|vomiting
🤧	0	打喷嚏|喷嚏|打喷嚏的脸|生病|脸|鼻涕	sneezing face|face|fever|flu|gesundheit|sick|sneeze|sneezing
🥵	0	脸发烧|中暑|冒汗|出汗|发烧|发热|吐舌|心狂跳|热|脸红	hot face|dying|face|feverish|heat|hot|panting|red-faced|stroke|sweating|tongue
🥶	0	冷脸|冰柱|冷|冷冰冰|冻|冻僵|满面寒霜|脸|脸色发青|蓝色|零下	cold face|blue|blue-faced|cold|face|freezing|frostbite|icicles|subzero|teeth
🥴	0	头昏眼花|两眼不平|喝醉|嘴唇颤抖|头晕目眩|头晕眼花|微醉|微醺|波浪嘴形|眩晕的脸|眼花|醉醺醺	woozy face|dizzy|drunk|eyes|face|intoxicated|mouth|tipsy|uneven|wavy|woozy
😵	0	晕头转向|头晕|头晕眼花|晕头|晕头的脸|脸	face with crossed-out eyes|crossed-out|dead|dizzy|eyes|face|feels|knocked|out|sick|tired
😵‍💫	0	晕|哇|哎呀|头晕|笑脸|迷糊	face with spiral eyes|confused|dizzy|eyes|face|hypnotized|omg|smiley|spiral|trouble|whoa|woah|woozy
🤯	0	爆炸头|不可能|印象深刻|吓到了|惊吓|震惊	exploding head|blown|explode|exploding|head|mind|mindblown|no|shocked|way
🤠	0	牛仔帽脸|帽|牛仔|脸	cowboy hat face|cowboy|cowgirl|face|hat
🥳	0	聚会笑脸|号角|喝彩|帽子|庆祝|派对|狂欢的脸|生日|聚会|脸|节日快乐	partying face|bday|birthday|celebrate|celebration|excited|face|happy|hat|hooray|horn|party|partying
🥸	0	伪装的脸|人物|伪装|眉毛|眼镜|胡子|脸|间谍|隐瞒身份|鼻子	disguised face|disguise|eyebrow|face|glasses|incognito|moustache|mustache|nose|person|spy|tache|tash
😎	0	墨镜笑脸|太阳镜|眼镜|耶|脸|酷|墨镜	smiling face with sunglasses|awesome|beach|bright|bro|chilling|cool|face|rad|relaxed|shades|slay|smile|style|sunglasses|swag|win
🤓	0	书呆子脸|专家|书呆子|天才|奇葩|宅男|极客|眼镜|眼镜笑脸|聪明|脸	nerd face|brainy|clever|expert|face|geek|gifted|glasses|intelligent|nerd|smart
🧐	0	带单片眼镜的脸|单眼镜|古板|奢华|富有|戴单眼镜的脸	face with monocle|classy|face|fancy|monocle|rich|stuffy|wealthy
😕	0	困扰|不懂|不确定|困惑|疑惑|脸	confused face|befuddled|confused|confusing|dunno|face|frown|hm|meh|not|sad|sorry|sure
🫤	0	郁闷|不相信|不确定|困惑|失望|怀疑|无所谓|无聊|沮丧|疑惑|迷惘	face with diagonal mouth|confused|confusion|diagonal|disappointed|doubt|doubtful|face|frustrated|frustration|meh|mouth|skeptical|unsure|whatever|wtv
😟	0	担心|不高兴|伤心|忧心的脸|意外|担忧|焦虑|紧张|脸	worried face|anxious|butterflies|face|nerves|nervous|sad|stress|stressed|surprised|worried|worry
🙁	0	微微不满|不开心|不高兴|不高兴的脸|委屈|小委屈|心情不好|脸	slightly frowning face|face|frown|frowning|sad|slightly
☹️	0	不满|不爽|不高兴|委屈|皱眉|皱眉的脸|脸	frowning face|face|frown|frowning|sad
😮	0	吃惊|同情|啊|忘记|我不信|我的天|脸	face with open mouth|believe|face|forgot|mouth|omg|open|shocked|surprised|sympathy|unbelievable|unreal|whoa|wow|you
😯	0	缄默|吃惊|哦|我的天|脸|静而无语	hushed face|epic|face|hushed|omg|stunned|surprised|whoa|woah
😲	0	震惊|不可以|惊|惊讶|惊讶的脸|没可能|绝不|脸	astonished face|astonished|cost|face|no|omg|shocked|totally|way
😳	0	脸红|困惑|天呀|害羞|羞涩|脸|茫然|迷茫|难以置信	flushed face|amazed|awkward|crazy|dazed|dead|disbelief|embarrassed|face|flushed|geez|heat|hot|impressed|jeez|what|wow
🥺	0	恳求的脸|可怜兮兮的眼神|大眼睛|小狗的脸|怜悯|祈求|祈求的脸|脸|请求	pleading face|begging|big|eyes|face|mercy|not|pleading|please|pretty|puppy|sad|why
🥹	0	忍住泪水|哭泣|喜极而泣|尴尬|悲伤|情绪|感激|感谢|抗拒|拜托|生气|自豪	face holding back tears|admiration|aww|back|cry|embarrassed|face|feelings|grateful|gratitude|holding|joy|please|proud|resist|sad|tears
😦	0	啊|惊讶|意外|目瞪口呆|脸	frowning face with open mouth|caught|face|frown|frowning|guard|mouth|open|scared|scary|surprise|what|wow
😧	0	极度痛苦|痛|痛啊|痛苦|脸|难受	anguished face|anguished|face|forgot|scared|scary|stressed|surprise|unhappy|what|wow
😨	0	害怕|不安|怕|恐怖|恐惧|脸	fearful face|afraid|anxious|blame|face|fear|fearful|scared|worried
😰	0	冷汗|张嘴冒冷汗的脸|惊讶|无语|汗|焦虑|紧张|脸	anxious face with sweat|anxious|blue|cold|eek|face|mouth|nervous|open|rushed|scared|sweat|yikes
😥	0	失望但如释重负|下次吧|出冷汗|失望|失望但解脱|如释重负|脸	sad but relieved face|anxious|call|close|complicated|disappointed|face|not|relieved|sad|sweat|time|whew
😢	0	哭|伤心|哀伤|哭脸|泪|脸	crying face|awful|cry|crying|face|feels|miss|sad|tear|triste|unhappy
😭	0	放声大哭|哭|大哭|放声大哭的脸|泪|痛哭|脸	loudly crying face|bawling|cry|crying|face|loudly|sad|sob|tear|tears|unhappy
😱	0	吓死了|吓死|害怕|尖叫|恐怖|惊吓大叫的脸|脸	face screaming in fear|epic|face|fear|fearful|munch|scared|scream|screamer|screaming|shocked|surprised|woah
😖	0	困惑|困惑的脸|焦头烂额|纠结|脸	confounded face|annoyed|confounded|confused|cringe|distraught|face|feels|frustrated|mad|sad
😣	0	痛苦|专注|入定|头痛|忍耐|脸|难受	persevering face|concentrate|concentration|face|focus|headache|persevere|persevering
😞	0	失望|不高兴|失望的脸|脸|难过	disappointed face|awful|blame|dejected|disappointed|face|fail|losing|sad|unhappy
😓	0	汗|冒冷汗|冒汗|冷|尴尬|担心|脸	downcast face with sweat|close|cold|downcast|face|feels|headache|nervous|sad|scared|sweat|yikes
😩	0	累死了|疲倦|疲劳|疲惫|累|脸	weary face|crying|face|fail|feels|hungry|mad|nooo|sad|sleepy|tired|unhappy|weary
😫	0	累|倦容|疲倦|疲劳|疲惫|脸	tired face|cost|face|feels|nap|sad|sneeze|tired
🥱	0	打呵欠|呵欠|哈欠|困|困倦|夜里|打哈欠|打哈欠的脸|无聊|昏昏欲睡|晚安|疲倦|累	yawning face|bedtime|bored|face|goodnight|nap|night|sleep|sleepy|tired|whatever|yawn|yawning|zzz
😤	0	傲慢|不爽|愤怒|气炸了|胜利|自负|赢|趾高气昂	face with steam from nose|anger|angry|face|feels|fume|fuming|furious|fury|mad|nose|steam|triumph|unhappy|won
😡	0	怒火中烧|发火|发飙|怒|生气|脸	enraged face|anger|angry|enraged|face|feels|mad|maddening|pouting|rage|red|shade|unhappy|upset
😠	0	生气|不爽|不高兴|怒|愤怒|脸	angry face|anger|angry|blame|face|feels|frustrated|mad|maddening|rage|shade|unhappy|upset
🤬	0	嘴上有符号的脸|不爽|发誓|咒骂|生气|碎碎唸的脸|脸|诅咒	face with symbols on mouth|censor|cursing|cussing|face|mad|mouth|pissed|swearing|symbols
😈	0	恶魔微笑|幻想|微笑|犄角|神话故事|脸|邪魔	smiling face with horns|demon|devil|evil|face|fairy|fairytale|fantasy|horns|purple|shade|smile|smiling|tale
👿	0	生气的恶魔|带角的怒容|幻想|恶魔|犄角|脸|顽童	angry face with horns|angry|demon|devil|evil|face|fairy|fairytale|fantasy|horns|imp|mischievous|purple|shade|tale
💀	0	头骨|妖怪|怪兽|死亡|神话故事|脸|身体|骷髅	skull|body|dead|death|face|fairy|fairytale|i’m|lmao|monster|tale|yolo
☠️	0	骷髅|交叉股骨|头骨|妖怪|怪物|死亡|海盗|脸|骨头	skull and crossbones|bone|crossbones|dead|death|face|monster|skull
💩	0	大便|好臭|屎|怪物|粑粑|脸|臭	pile of poo|bs|comic|doo|dung|face|fml|monster|pile|poo|poop|smelly|smh|stink|stinks|stinky|turd
🤡	0	小丑脸|小丑|脸	clown face|clown|face
👹	0	食人魔|吓人|妖怪|幻想|日本|神话故事|脸|面具|鬼|魔鬼	ogre|creature|devil|face|fairy|fairytale|fantasy|mask|monster|scary|tale
👺	0	小妖精|妖怪|幻想|怪物|日本|神话故事|脸|鬼	goblin|angry|creature|face|fairy|fairytale|fantasy|mask|mean|monster|tale
👻	0	鬼|万圣节|妖怪|幻想|幽灵|怪物|神话故事|脸|鬼脸	ghost|boo|creature|excited|face|fairy|fairytale|fantasy|halloween|haunting|monster|scary|silly|tale
👽	0	外星人|ufo|外太空|外星|太空|幻想|星际|脸|飞碟	alien|creature|extraterrestrial|face|fairy|fairytale|fantasy|monster|space|tale|ufo
👾	0	外星怪物|ufo|外星|外星人|太空|怪物|星际|脸|飞碟	alien monster|alien|creature|extraterrestrial|face|fairy|fairytale|fantasy|game|gamer|games|monster|pixelated|space|tale|ufo
🤖	0	机器人|怪物|脸	robot|face|monster
😺	0	大笑的猫|哈哈|大笑的猫脸|猫脸|笑|脸	grinning cat|animal|cat|face|grinning|mouth|open|smile|smiling
😸	0	微笑的猫|呵呵|微笑的猫脸|猫脸|笑|笑颜逐开|脸	grinning cat with smiling eyes|animal|cat|eye|eyes|face|grin|grinning|smile|smiling
😹	0	笑出眼泪的猫|喜极而泣|快乐|猫脸|眼泪|笑出眼泪|笑出眼泪的猫脸|脸	cat with tears of joy|animal|cat|face|joy|laugh|laughing|lol|tear|tears
😻	0	花痴的猫|WC|喜欢|心|猫|猫脸|脸|花痴|花痴的猫脸	smiling cat with heart-eyes|animal|cat|eye|face|heart|heart-eyes|love|smile|smiling
😼	0	奸笑的猫|嘲讽笑容|奸笑|奸笑的猫脸|猫脸|脸|讽刺	cat with wry smile|animal|cat|face|ironic|smile|wry
😽	0	亲亲猫|亲亲|吻|猫脸|猫脸亲亲|脸|闭眼亲亲的猫脸	kissing cat|animal|cat|closed|eye|eyes|face|kiss|kissing
🙀	0	疲倦的猫|惊讶|猫脸|疲倦|疲倦的猫脸|疲劳|疲惫|累|脸	weary cat|animal|cat|face|oh|surprised|weary
😿	0	哭泣的猫|哭|哭泣的猫脸|泪|猫脸|眼泪|脸|难过	crying cat|animal|cat|cry|crying|face|sad|tear
😾	0	生气的猫|猫脸|生气|生气的猫脸|脸	pouting cat|animal|cat|face|pouting
🙈	0	非礼勿视|不许看|别看|尴尬|糗|脸|蒙住眼睛|蒙眼	see-no-evil monkey|embarrassed|evil|face|forbidden|forgot|gesture|hide|monkey|no|omg|prohibited|scared|secret|smh|watch
🙉	0	非礼勿听|嘘|堵上耳朵|堵耳|猴子|脸	hear-no-evil monkey|animal|ears|evil|face|forbidden|gesture|hear|listen|monkey|no|not|prohibited|secret|shh|tmi
🙊	0	非礼勿言|不许说|捂上嘴巴|捂嘴|秘密|脸	speak-no-evil monkey|animal|evil|face|forbidden|gesture|monkey|no|not|oops|prohibited|quiet|secret|speak|stealth
💌	0	情书|信|心|邮件	love letter|heart|letter|love|mail|romance|valentine
💘	0	心中箭了|一箭穿心|丘比特|我爱你|浪漫|爱情|箭|红心	heart with arrow|143|adorbs|arrow|cupid|date|emotion|heart|ily|love|romance|valentine
💝	0	系有缎带的心|我爱你|爱的礼物|绑丝带的心|送你一颗心	heart with ribbon|143|anniversary|emotion|heart|ily|kisses|ribbon|valentine|xoxo
💖	0	闪亮的心|我爱你|激动|红心|闪亮	sparkling heart|143|emotion|excited|good|heart|ily|kisses|morning|night|sparkle|sparkling|xoxo
💗	0	搏动的心|亲亲|吻|我爱你|搏动|激动|红心|紧张	growing heart|143|emotion|excited|growing|heart|heartpulse|ily|kisses|muah|nervous|pulse|xoxo
💓	0	心跳|心动|我爱你|爱	beating heart|143|beating|cardio|emotion|heart|heartbeat|ily|love|pulsating|pulse
💞	0	舞动的心|我爱你|旋转|涌动|跃动	revolving hearts|143|adorbs|anniversary|emotion|heart|hearts|revolving
💕	0	两颗心|我爱你|爱情	two hearts|143|anniversary|date|dating|emotion|heart|hearts|ily|kisses|love|loving|two|xoxo
💟	0	心型装饰|心|我爱你|装饰	heart decoration|143|decoration|emotion|heart|hearth|purple|white
❣️	0	心叹号|叹号|心动|标点符号	heart exclamation|exclamation|heart|heavy|mark|punctuation
💔	0	心碎|伤心	broken heart|break|broken|crushed|emotion|heart|heartbroken|lonely|sad
❤️‍🔥	0	火上之心|渴望|燃烧|爱	heart on fire|burn|fire|heart|love|lust|sacred
❤️‍🩹	0	修复受伤的心灵|修补|恢复|痊愈	mending heart|healthier|heart|improving|mending|recovering|recuperating|well
❤️	0	红心|心|爱	red heart|emotion|heart|love|red
🩷	0	粉红色的心|可爱|喜欢|心|感情|我爱你|爱|特殊|甜蜜|粉红|讨人喜欢	pink heart|143|adorable|cute|emotion|heart|ily|like|love|pink|special|sweet
🧡	0	橙心|橘心|橘色|橘色的心|橙	orange heart|143|heart|orange
💛	0	黄心|我爱你|黄	yellow heart|143|cardiac|emotion|heart|ily|love|yellow
💚	0	绿心|我爱你|绿	green heart|143|emotion|green|heart|ily|love|romantic
💙	0	蓝心|我爱你|蓝	blue heart|143|blue|emotion|heart|ily|love|romance
🩵	0	浅蓝色的心|可爱|喜欢|天蓝|心|感情|我爱你|浅蓝|爱|特殊|蓝绿|蓝绿色|青色	light blue heart|143|blue|cute|cyan|emotion|heart|ily|light|like|love|sky|special|teal
💜	0	紫心|我爱你|紫	purple heart|143|bestest|emotion|heart|ily|love|purple
🤎	0	棕心|心|心形|棕|棕色|棕色爱心|爱心	brown heart|143|brown|heart
🖤	0	黑心|心|邪恶|黑|黑色|黑色的心	black heart|black|evil|heart|wicked
🩶	0	灰心|心|感情|我爱你|暗灰|灰|灰色|爱|特殊|银|银色	grey heart|143|emotion|gray|grey|heart|ily|love|silver|slate|special
🤍	0	白心|心|心形|爱心|白|白色|白色爱心	white heart|143|heart|white
💋	0	唇印|亲吻|吻|唇|性感|接吻|浪漫	kiss mark|dating|emotion|heart|kiss|kissing|lips|mark|romance|sexy
💯	0	一百分|100|满分|百分百|绝对|考试	hundred points|100|a+|agree|clearly|definitely|faithful|fleek|full|hundred|keep|perfect|point|score|true|truth|yup
💢	0	怒|火大|生气|青筋	anger symbol|anger|angry|comic|mad|symbol|upset
💥	0	爆炸|撞|旺|炸|爆	collision|bomb|boom|collide|comic|explode
💫	0	头晕|头晕目眩|星星|流星	dizzy|comic|shining|shooting|star|stars
💦	0	汗滴|喷溅|小水滴|小水珠|汗|泼贱|溅	sweat droplets|comic|drip|droplet|droplets|drops|splashing|squirt|sweat|water|wet|work|workout
💨	0	尾气|扬尘而去|放屁|烟|疾驰而去|飞奔而去	dashing away|away|cloud|comic|dash|dashing|fart|fast|go|gone|gotta|running|smoke
🕳️	0	洞|井盖|坑|陷阱	hole
💬	0	话语气泡|发言|对话框|气泡|气泡对话框|气球|漫画	speech balloon|balloon|bubble|comic|dialog|message|sms|speech|talk|text|typing
👁️‍🗨️	0	眼睛对话框|对话框|目擊|眼睛	eye in speech bubble|balloon|bubble|eye|speech|witness
🗨️	0	朝左的话语气泡|对话框|话语	left speech bubble|balloon|bubble|dialog|left|speech
🗯️	0	愤怒话语气泡|右倾愤怒对话框|对话框|愤怒	right anger bubble|anger|angry|balloon|bubble|mad|right
💭	0	内心活动气泡|对话框|思想|思想活动|想法|梦|气泡|泡泡对话框|白日梦	thought balloon|balloon|bubble|cartoon|cloud|comic|daydream|decisions|dream|idea|invent|invention|realize|think|thoughts|wonder
💤	0	睡着|呼噜|困了|想睡|打呼|晚安|疲倦	zzz|comic|good|goodnight|night|sleep|sleeping|sleepy|tired|zzz
👋	1	挥手|你好|再见|嗨|在吗|手|等一下|等等|该走了	waving hand|bye|cya|g2g|greetings|gtg|hand|hello|hey|hi|later|outtie|ttfn|ttyl|wave|yo|you
🤚	1	立起的手背|举起|举起手背|手|手背|立起	raised back of hand|back|backhand|hand|raised
🖐️	1	手掌|举起张开的手掌|击掌|布|手|禁止	hand with fingers splayed|finger|fingers|hand|raised|splayed|stop
✋	1	举起手|举手|举起的手|五指|停|击掌|手	raised hand|5|five|hand|high|raised|stop
🖖	1	瓦肯举手礼|手|敬礼|斯波克|星际迷航|瓦肯	vulcan salute|finger|hand|hands|salute|vulcan
🫱	1	向右的手|伸手|右|右手|向右|手|握手	rightwards hand|hand|handshake|hold|reach|right|rightward|rightwards|shake
🫲	1	向左的手|伸手|向左|左|左手|手|握手	leftwards hand|hand|handshake|hold|left|leftward|leftwards|reach|shake
🫳	1	掌心向下的手|下投|手|扔掉|拿起|捡起|解散|驱赶	palm down hand|dismiss|down|drop|dropped|hand|palm|pick|shoo|up
🫴	1	掌心向上的手|不知道|召唤|告诉我|手|拿着|接住|提供|过来|送出	palm up hand|beckon|catch|come|hand|hold|know|lift|me|offer|palm|tell
🫷	1	向左推|中止|停止|击掌|向左|往左|手|拒绝|推|暂停|等等|阻挡	leftwards pushing hand|block|five|halt|hand|high|hold|leftward|leftwards|pause|push|pushing|refuse|slap|stop|wait
🫸	1	向右推|中止|停止|击掌|向右|往右|手|拒绝|推|暂停|等等|阻挡	rightwards pushing hand|block|five|halt|hand|high|hold|pause|push|pushing|refuse|rightward|rightwards|slap|stop|wait
👌	1	OK|OK 手势|可以|同意|好的|当然|手|没问题|确定	ok hand|awesome|bet|dope|fleek|fosho|got|gotcha|hand|legit|ok|okay|pinch|rad|sure|sweet|three
🤌	1	捏手指|为什么|你到底在说什么|匮乏|审讯|强调|您要什么|手势|手指|挖苦|放松点	pinched fingers|fingers|gesture|hand|hold|huh|interrogation|patience|pinched|relax|sarcastic|ugh|what|zip
🤏	1	捏合的手势|一点|一点点|小|少|少量|手指|捏着|某种程度上	pinching hand|amount|bit|fingers|hand|little|pinching|small|sort
✌️	1	胜利手势|V|和平|成功|手|胜利	victory hand|hand|peace|v|victory
🤞	1	交叉的手指|交叉|幸运|手|手指|祝好运	crossed fingers|cross|crossed|finger|fingers|hand|luck
🫰	1	食指与拇指交叉的手|响指|心|手|昂贵|比心|爱|爱心|金钱|钞票	hand with index finger and thumb crossed|<3|crossed|expensive|finger|hand|heart|index|love|money|snap|thumb
🤟	1	爱你的手势|三种|我爱你|手|爱你	love-you gesture|fingers|gesture|hand|ily|love|love-you|three|you
🤘	1	摇滚|手|摇滚精神|燥起来|角|金属礼	sign of the horns|finger|hand|horns|rock-on|sign
🤙	1	给我打电话|手|打电话给我|电话|给我打电话的手势	call me hand|call|hand|hang|loose|me|shaka
👈	1	反手食指向左指|反手|向左指|手|指左|食指	backhand index pointing left|backhand|finger|hand|index|left|point|pointing
👉	1	反手食指向右指|反手|向右指|手|指右|食指	backhand index pointing right|backhand|finger|hand|index|point|pointing|right
👆	1	反手食指向上指|反手|向上指|手|指上|食指	backhand index pointing up|backhand|finger|hand|index|point|pointing|up
🖕	1	竖中指|中指|反手|手	middle finger|finger|hand|middle
👇	1	反手食指向下指|反手|向下指|手|指下|食指	backhand index pointing down|backhand|down|finger|hand|index|point|pointing
☝️	1	食指向上指|向上指|手|指上|食指	index pointing up|finger|hand|index|point|pointing|this|up
🫵	1	指向观察者的食指|伸出手指|你|戳|手指|指|指向	index pointing at the viewer|at|finger|hand|index|pointing|poke|viewer|you
👍	1	拇指向上|同意|好|手|拇指|真棒|赞|赞成|顶一下	thumbs up|+1|good|hand|like|thumb|up|yes
👎	1	拇指向下|不赞成|反对|否决|手|责备	thumbs down|-1|bad|dislike|down|good|hand|no|nope|thumb|thumbs
✊	1	举起拳头|举拳|团结|手|拳头|握拳	raised fist|clenched|fist|hand|punch|raised|solidarity
👊	1	出拳|完全同意|手|打|拳|挥拳过来|绝对正确	oncoming fist|absolutely|agree|boom|bro|bruh|bump|clenched|correct|fist|hand|knuckle|oncoming|pound|punch|rock|ttyl
🤛	1	朝左的拳头|拳头|朝左	left-facing fist|fist|left-facing|leftwards
🤜	1	朝右的拳头|手|拳头|朝右	right-facing fist|fist|right-facing|rightwards
👏	1	鼓掌|干得好|恭喜|拍手|赞成	clapping hands|applause|approval|awesome|clap|congrats|congratulations|excited|good|great|hand|homie|job|nice|prayed|well|yay
🙌	1	举双手|举手|击掌|双手|庆祝|手	raising hands|celebration|gesture|hand|hands|hooray|praise|raised|raising
🫶	1	做成心形的双手|手|比心|爱|爱你|爱心	heart hands|<3|hands|heart|love|you
👐	1	张开双手|十|双手|摊手	open hands|hand|hands|hug|jazz|open|swerve
🤲	1	掌心向上托起|双掌|双掌向上|希望|祈祷|祷告	palms up together|cupped|dua|hands|palms|pray|prayer|together|up|wish
🤝	1	握手|一言为定|会面|协议|君子协定	handshake|agreement|deal|hand|meeting|shake
🙏	1	双手合十|合掌|感恩|拜托|祈求|祈祷|祈福|祝福|谢谢	folded hands|appreciate|ask|beg|blessed|bow|cmon|five|folded|gesture|hand|high|please|pray|thanks|thx
✍️	1	写字|写|手|笔	writing hand|hand|write|writing
💅	1	涂指甲油|修指甲|忙完了|护手|指甲油|美甲|闷|随便啦	nail polish|bored|care|cosmetics|done|makeup|manicure|nail|polish|whatever
🤳	1	自拍|手机|相机	selfie|camera|phone
💪	1	肌肉|二头肌|健身房|强壮	flexed biceps|arm|beast|bench|biceps|bodybuilder|bro|curls|flex|gains|gym|jacked|muscle|press|ripped|strong|weightlift
🦾	0	机械手臂|义肢|手臂|无障碍	mechanical arm|accessibility|arm|mechanical|prosthetic
🦿	0	机械腿|义肢|无障碍|腿	mechanical leg|accessibility|leg|mechanical|prosthetic
🦵	1	腿|弯腿|肢体|脚|跛行|踢	leg|bent|foot|kick|knee|limb
🦶	1	脚|足踝|踏|踝|踢|踩|踱	foot|ankle|feet|kick|stomp
👂	1	耳朵|仔细听|听|耳	ear|body|ears|hear|hearing|listen|listening|sound
🦻	1	戴助听器的耳朵|助听器|听力障碍|听障|失聪|无障碍|耳聋|聋	ear with hearing aid|accessibility|aid|ear|hard|hearing
👃	1	鼻子|嗅|气味|闻|鼻	nose|body|noses|nosey|odor|smell|smells
🧠	0	脑|大脑|头脑|智慧|智能|聪明	brain|intelligent|smart
🫀	0	心脏器官|中心|器官|心率|心脏|心脏病学|心跳|真心|红心|解剖|身体	anatomical heart|anatomical|beat|cardiology|heart|heartbeat|organ|pulse|real|red
🫁	0	肺|吸气|呼吸|呼吸作用|呼气|器官|肺部|身体	lungs|breath|breathe|exhalation|inhalation|lung|organ|respiration
🦷	0	牙齿|牙医|牙科医生|珍珠色|白色	tooth|dentist|pearly|teeth|white
🦴	0	骨头|叉骨|狗|骨骼	bone|bones|dog|skeleton|wishbone
👀	0	双眼|看|眼睛|窥视|身体	eyes|body|eye|face|googly|look|looking|omg|peep|see|seeing
👁️	0	眼睛|单眼|看|眼|身体	eye|1|body|one
👅	0	舌头|啧啧地喝|舌|舔|身体	tongue|body|lick|slurp
👄	0	嘴|口|口红|吻|唇|唇膏	mouth|beauty|body|kiss|kissing|lips|lipstick
🫦	0	咬住嘴唇|不舒服|口红|咬嘴唇|嘴唇|害怕|性感|担心|接吻|焦虑|紧张|调情	biting lip|anxious|bite|biting|fear|flirt|flirting|kiss|lip|lipstick|nervous|sexy|uncomfortable|worried|worry
👶	1	小宝贝|孩子|宝宝|小毛头	baby|babies|children|goo|infant|newborn|pregnant|young
🧒	1	儿童|中性|小孩|年轻人|性别不明|性别中立	child|bright-eyed|grandchild|kid|young|younger
👦	1	男孩|儿童|孩子|小孩|男	boy|bright-eyed|child|grandson|kid|son|young|younger
👧	1	女孩|儿童|大眼女孩|女|女儿|孩子|小孩	girl|bright-eyed|child|daughter|granddaughter|kid|virgo|young|younger|zodiac
🧑	1	成人|中性|性别中立|性格不明	person|adult
👱	1	金色头发的人|人|脸|金发	person: blond hair|blond|blond-haired|human|person
👨	1	男人|兄弟|成人|男	man|adult|bro
🧔	1	有胡子的人|人|大胡子|男|络腮胡|胡子|胡须|腮帮子|连鬓胡子	person: beard|beard|bearded|person|whiskers
🧔‍♂️	1	有络腮胡子的男人|男人|胡子	man: beard|beard|bearded|man|whiskers
🧔‍♀️	1	有络腮胡子的女人|女人|胡子	woman: beard|beard|bearded|whiskers|woman
👨‍🦰	1	男人: 红发|兄弟|成人|男|男人|红发	man: red hair|adult|bro|man|red hair
👨‍🦱	1	男人: 卷发|兄弟|卷发|成人|男|男人	man: curly hair|adult|bro|curly hair|man
👨‍🦳	1	男人: 白发|兄弟|成人|男|男人|白发	man: white hair|adult|bro|man|white hair
👨‍🦲	1	男人: 秃顶|兄弟|成人|男|男人|秃顶	man: bald|adult|bald|bro|man
👩	1	女人|女|淑女|金发	woman|adult|lady
👩‍🦰	1	女人: 红发|女|女人|淑女|红发|金发	woman: red hair|adult|lady|red hair|woman
🧑‍🦰	1	成人: 红发|中性|性别中立|性格不明|成人|红发	person: red hair|adult|person|red hair
👩‍🦱	1	女人: 卷发|卷发|女|女人|淑女|金发	woman: curly hair|adult|curly hair|lady|woman
🧑‍🦱	1	成人: 卷发|中性|卷发|性别中立|性格不明|成人	person: curly hair|adult|curly hair|person
👩‍🦳	1	女人: 白发|女|女人|淑女|白发|金发	woman: white hair|adult|lady|white hair|woman
🧑‍🦳	1	成人: 白发|中性|性别中立|性格不明|成人|白发	person: white hair|adult|person|white hair
👩‍🦲	1	女人: 秃顶|女|女人|淑女|秃顶|金发	woman: bald|adult|bald|lady|woman
🧑‍🦲	1	成人: 秃顶|中性|性别中立|性格不明|成人|秃顶	person: bald|adult|bald|person
👱‍♀️	1	金发女|女|金发	woman: blond hair|blond|blond-haired|blonde|hair|woman
👱‍♂️	1	金发男|男|金发	man: blond hair|blond|blond-haired|hair|man
🧓	1	老年人|中性|性别不明|性别中性|成人|熟龄|老人|老男人|老龄	older person|adult|elderly|grandparent|old|person|wise
👴	1	老爷爷|祖父|秃头|老人|老头	old man|adult|bald|elderly|gramps|grandfather|grandpa|man|old|wise
👵	1	老奶奶|祖母|老人|老太	old woman|adult|elderly|grandma|grandmother|granny|lady|old|wise|woman
🙍	1	皱眉|不开心|不满|不爽|失望|心烦意乱|恼火|沮丧|皱眉的人	person frowning|annoyed|disappointed|disgruntled|disturbed|frown|frowning|frustrated|gesture|irritated|person|upset
🙍‍♂️	1	皱眉男|不开心|男|皱眉|表情	man frowning|annoyed|disappointed|disgruntled|disturbed|frown|frowning|frustrated|gesture|irritated|man|upset
🙍‍♀️	1	皱眉女|不开心|女|皱眉	woman frowning|annoyed|disappointed|disgruntled|disturbed|frown|frowning|frustrated|gesture|irritated|upset|woman
🙎	1	撅嘴|不开心|不高兴|低落|噘嘴|失望|怒视|撅嘴的人|生闷气|皱眉|苦相|表情	person pouting|disappointed|downtrodden|frown|grimace|person|pouting|scowl|sulk|upset|whine
🙎‍♂️	1	撅嘴男|不开心|噘嘴|男|表情	man pouting|disappointed|downtrodden|frown|grimace|man|pouting|scowl|sulk|upset|whine
🙎‍♀️	1	撅嘴女|不开心|噘嘴|女	woman pouting|disappointed|downtrodden|frown|grimace|pouting|scowl|sulk|upset|whine|woman
🙅	1	禁止手势|不允许|不可能|不行|不通过|反对|手|用手势表示不的人|禁止	person gesturing no|forbidden|gesture|hand|no|not|person|prohibit
🙅‍♂️	1	禁止手势男|不行|反对|男|禁止	man gesturing no|forbidden|gesture|hand|man|no|not|prohibit
🙅‍♀️	1	禁止手势女|不行|反对|女|禁止	woman gesturing no|forbidden|gesture|hand|no|not|prohibit|woman
🙆	1	OK手势|ok|同意|女子用手势表示好|好的|手|手势|摆姿势|锻炼	person gesturing ok|exercise|gesture|gesturing|hand|ok|omg|person
🙆‍♂️	1	OK手势男|ok|OK|ok手势男|可以|同意|好的|男|运动	man gesturing ok|exercise|gesture|gesturing|hand|man|ok|omg
🙆‍♀️	1	OK手势女|OK|可以|同意|女|好的	woman gesturing ok|exercise|gesture|gesturing|hand|ok|omg|woman
💁	1	前台|介绍|伸手给小费|信息|八卦|帮助|手|拨弄头发|自信时髦|请您离开|随便啦	person tipping hand|fetch|flick|flip|gossip|hand|person|sarcasm|sarcastic|sassy|seriously|tipping|whatever
💁‍♂️	1	前台男|前台|嘲讽|小费|男	man tipping hand|fetch|flick|flip|gossip|hand|man|sarcasm|sarcastic|sassy|seriously|tipping|whatever
💁‍♀️	1	前台女|前台|女	woman tipping hand|fetch|flick|flip|gossip|hand|sarcasm|sarcastic|sassy|seriously|tipping|whatever|woman
🙋	1	举手|举手的人|嗨|开心|我参加|我可以帮忙|我知道|手|看这里|选我	person raising hand|gesture|hand|here|know|me|person|pick|question|raise|raising
🙋‍♂️	1	男生举手|举手|发问|手势|男	man raising hand|gesture|hand|here|know|man|me|pick|question|raise|raising
🙋‍♀️	1	女生举手|举手|女	woman raising hand|gesture|hand|here|know|me|pick|question|raise|raising|woman
🧏	1	失聪者|听力|听力障碍|听障|无障碍|耳朵|耳聋|聋	deaf person|accessibility|deaf|ear|gesture|hear|person
🧏‍♂️	1	失聪的男人|听力障碍|男|耳朵|聋	deaf man|accessibility|deaf|ear|gesture|hear|man
🧏‍♀️	1	失聪的女人|听力障碍|女|耳朵|聋	deaf woman|accessibility|deaf|ear|gesture|hear|woman
🙇	1	鞠躬|不好意思|冥想|姿势|对不起|惭愧|感谢|懊悔|祈求宽恕|道歉|鞠躬的人	person bowing|apology|ask|beg|bow|bowing|favor|forgive|gesture|meditate|meditation|person|pity|regret|sorry
🙇‍♂️	1	男生鞠躬|不好意思|对不起|男|道歉	man bowing|apology|ask|beg|bow|bowing|favor|forgive|gesture|man|meditate|meditation|pity|regret|sorry
🙇‍♀️	1	女生鞠躬|不好意思|女|对不起|道歉|静思|鞠躬	woman bowing|apology|ask|beg|bow|bowing|favor|forgive|gesture|meditate|meditation|pity|regret|sorry|woman
🤦	1	捂脸|人|尴尬|恼怒|我的天哪|扶额|无语|难以置信|震惊	person facepalming|again|bewilder|disbelief|exasperation|facepalm|no|not|oh|omg|person|shock|smh
🤦‍♂️	1	男生捂脸|尴尬|恼怒|我的天哪|扶额|捂脸|无奈|无语|男|男子捂脸|难以置信|震惊	man facepalming|again|bewilder|disbelief|exasperation|facepalm|man|no|not|oh|omg|shock|smh
🤦‍♀️	1	女生捂脸|女|女子捂脸|尴尬|恼怒|我的天哪|扶额|捂脸|无奈|无语|难以置信|震惊	woman facepalming|again|bewilder|disbelief|exasperation|facepalm|no|not|oh|omg|shock|smh|woman
🤷	1	耸肩|不关心|不知道|人|天晓得|怀疑|我哪知|我猜的|无所谓|无视	person shrugging|doubt|dunno|guess|idk|ignorance|indifference|knows|maybe|person|shrug|shrugging|whatever|who
🤷‍♂️	1	男生耸肩|不关心|不知道|天晓得|怀疑|我哪知|我猜的|无所谓|无视|男|男子耸肩|耸肩	man shrugging|doubt|dunno|guess|idk|ignorance|indifference|knows|man|maybe|shrug|shrugging|whatever|who
🤷‍♀️	1	女生耸肩|不关心|不知道|天晓得|女|女子耸肩|怀疑|我哪知|我猜的|无所谓|无视|耸肩	woman shrugging|doubt|dunno|guess|idk|ignorance|indifference|knows|maybe|shrug|shrugging|whatever|who|woman
🧑‍⚕️	1	卫生工作者|医生|护士|治疗师	health worker|doctor|health|healthcare|nurse|therapist|worker
👨‍⚕️	1	男医生|医护人员|医生|护士|治疗师|男|男人|男治疗师	man health worker|doctor|health|healthcare|man|nurse|therapist|worker
👩‍⚕️	1	女医生|医护人员|医生|女|女人|女治疗师|护士|治疗师	woman health worker|doctor|health|healthcare|nurse|therapist|woman|worker
🧑‍🎓	1	学生|毕业|毕业生	student|graduate
👨‍🎓	1	男学生|学生|毕业|男	man student|graduate|man|student
👩‍🎓	1	女学生|女|学生|毕业	woman student|graduate|student|woman
🧑‍🏫	1	老师|教师|教授	teacher|instructor|lecturer|professor
👨‍🏫	1	男老师|教师|教授|男|老师	man teacher|instructor|lecturer|man|professor|teacher
👩‍🏫	1	女老师|女|教师|教授|老师	woman teacher|instructor|lecturer|professor|teacher|woman
🧑‍⚖️	1	法官|法律	judge|justice|law|scales
👨‍⚖️	1	男法官|正义|法官|法律|男	man judge|judge|justice|law|man|scales
👩‍⚖️	1	女法官|女|正义|法官|法律	woman judge|judge|justice|law|scales|woman
🧑‍🌾	1	农民|园丁	farmer|gardener|rancher
👨‍🌾	1	农夫|农民|园丁|牧场主人|牧场工人|男	man farmer|farmer|gardener|man|rancher
👩‍🌾	1	农妇|农民|园丁|女|牧场主人|牧场工	woman farmer|farmer|gardener|rancher|woman
🧑‍🍳	1	厨师|做饭|大厨	cook|chef
👨‍🍳	1	男厨师|做饭|厨师|大厨|男	man cook|chef|cook|man
👩‍🍳	1	女厨师|做饭|厨师|大厨|女	woman cook|chef|cook|woman
🧑‍🔧	1	技工|水管工|电工	mechanic|electrician|plumber|tradesperson
👨‍🔧	1	男技工|技工|机械工|杂工|水管工|水管工人|电工|男	man mechanic|electrician|man|mechanic|plumber|tradesperson
👩‍🔧	1	女技工|修理工|女|技工|水电工|水管工|水管工人|电工	woman mechanic|electrician|mechanic|plumber|tradesperson|woman
🧑‍🏭	1	工人|工业|工厂|装配	factory worker|assembly|factory|industrial|worker
👨‍🏭	1	男工人|工业|工人|工厂|男|组装工|装配	man factory worker|assembly|factory|industrial|man|worker
👩‍🏭	1	女工人|女|工业|工人|工厂|装配	woman factory worker|assembly|factory|industrial|woman|worker
🧑‍💼	1	白领|商人|建筑师|经理	office worker|architect|business|manager|office|white-collar|worker
👨‍💼	1	男白领|商人|建筑师|男|白领|经理	man office worker|architect|business|man|manager|office|white-collar|worker
👩‍💼	1	女白领|人物|商人|女|建筑师|白领|经理	woman office worker|architect|business|manager|office|white-collar|woman|worker
🧑‍🔬	1	科学家|化学家|工程学家|物理学家|生物学家	scientist|biologist|chemist|engineer|mathematician|physicist
👨‍🔬	1	男科学家|化学家|工程学家|工程师|数学家|物理学家|生物学家|男|科学家	man scientist|biologist|chemist|engineer|man|mathematician|physicist|scientist
👩‍🔬	1	女科学家|化学家|女|工程学家|工程师|数学家|物理学家|生物学家|科学家	woman scientist|biologist|chemist|engineer|mathematician|physicist|scientist|woman
🧑‍💻	1	程序员|发明|开发人员|码农|软件	technologist|coder|computer|developer|inventor|software
👨‍💻	1	男程序员|发明家|工程师|开发人员|男|码农|程序员|软件	man technologist|coder|computer|developer|inventor|man|software|technologist
👩‍💻	1	女程序员|发明家|女|工程师|开发人员|码农|程序员|软件	woman technologist|coder|computer|developer|inventor|software|technologist|woman
🧑‍🎤	1	歌手|摇滚歌手|明星|演员|艺人	singer|actor|entertainer|rock|rockstar|star
👨‍🎤	1	男歌手|摇滚歌手|明星|歌手|男|男演员|艺人	man singer|actor|entertainer|man|rock|rockstar|singer|star
👩‍🎤	1	女歌手|女|摇滚歌手|明星|歌手|演员|艺人	woman singer|actor|entertainer|rock|rockstar|singer|star|woman
🧑‍🎨	1	艺术家|画家	artist|palette
👨‍🎨	1	男艺术家|男|画家|艺术	man artist|artist|man|palette
👩‍🎨	1	女艺术家|女|画家|艺术	woman artist|artist|palette|woman
🧑‍✈️	1	飞行员|飞机	pilot|plane
👨‍✈️	1	男飞行员|机长|男|飞机|飞行员	man pilot|man|pilot|plane
👩‍✈️	1	女飞行员|女|机长|飞机|飞行员	woman pilot|pilot|plane|woman
🧑‍🚀	1	宇航员|火箭	astronaut|rocket|space
👨‍🚀	1	男宇航员|宇宙|宇航员|火箭|男|航天	man astronaut|astronaut|man|rocket|space
👩‍🚀	1	女宇航员|女|宇宙|宇航员|火箭|航天	woman astronaut|astronaut|rocket|space|woman
🧑‍🚒	1	消防员|消防车	firefighter|fire|firetruck
👨‍🚒	1	男消防员|救火|消防|消防员|消防车|男	man firefighter|fire|firefighter|firetruck|man
👩‍🚒	1	女消防员|女|救火|消防|消防员|消防车|火灾	woman firefighter|fire|firefighter|firetruck|woman
👮	1	警察|交警|传唤|公安|卧底|武警|法警|警官|警方|逮捕	police officer|apprehend|arrest|citation|cop|law|officer|over|police|pulled|undercover
👮‍♂️	1	男警察|男|警官|警察	man police officer|apprehend|arrest|citation|cop|law|man|officer|over|police|pulled|undercover
👮‍♀️	1	女警察|交警|公安|卧底|女|武警|法警|警官|警察|警方|逮捕	woman police officer|apprehend|arrest|citation|cop|law|officer|over|police|pulled|undercover|woman
🕵️	1	侦探|特工|男|间谍	detective|sleuth|spy
🕵️‍♂️	1	男侦探|侦探|男|间谍	man detective|detective|man|sleuth|spy
🕵️‍♀️	1	女侦探|侦探|女|特工|间谍	woman detective|detective|sleuth|spy|woman
💂	1	卫兵|伦敦|卫士|守卫|白金汉宫	guard|buckingham|helmet|london|palace
💂‍♂️	1	男卫兵|卫兵|卫士|守卫|男	man guard|buckingham|guard|helmet|london|man|palace
💂‍♀️	1	女卫兵|卫兵|卫士|女|守卫	woman guard|buckingham|guard|helmet|london|palace|woman
🥷	1	忍者|人物|侠客|刺客|士兵|战斗|打斗|狡猾|秘密|隐藏|隐身	ninja|assassin|fight|fighter|hidden|person|secret|skills|sly|soldier|stealth|war
👷	1	建筑工人|包工头|头盔|安全帽|工人|工程师|建筑|建造|搬砖|改造	construction worker|build|construction|fix|hardhat|hat|man|person|rebuild|remodel|repair|work|worker
👷‍♂️	1	男建筑工人|工人|建筑|男	man construction worker|build|construction|fix|hardhat|hat|man|rebuild|remodel|repair|work|worker
👷‍♀️	1	女建筑工人|头盔|女|工人|建筑	woman construction worker|build|construction|fix|hardhat|hat|man|rebuild|remodel|repair|woman|work|worker
🫅	1	戴王冠的人|君主|君威|国王|王冠|王后|王室|皇室|贵族	person with crown|crown|monarch|noble|person|regal|royal|royalty
🤴	1	王子|皇家	prince|crown|fairy|fairytale|fantasy|king|royal|royalty|tale
👸	1	公主|皇冠|童话	princess|crown|fairy|fairytale|fantasy|queen|royal|royalty|tale
👳	1	戴头巾的人|头巾	person wearing turban|person|turban|wearing
👳‍♂️	1	戴头巾的男人|头巾|男	man wearing turban|man|turban|wearing
👳‍♀️	1	戴头巾的女人|头巾|女|特本	woman wearing turban|turban|wearing|woman
👲	1	戴瓜皮帽的人|人物|帽子|瓜皮帽	person with skullcap|cap|chinese|gua|guapi|hat|mao|person|pi|skullcap
🧕	1	带头饰的女人|头巾|希贾布|戴头巾的女人	woman with headscarf|bandana|head|headscarf|hijab|kerchief|mantilla|tichel|woman
🤵	1	穿燕尾服的人|人|新郎|正式|燕尾服|男人|穿燕尾服的男人	person in tuxedo|formal|person|tuxedo|wedding
🤵‍♂️	1	穿礼服的男人|男人|礼服	man in tuxedo|formal|groom|man|tuxedo|wedding
🤵‍♀️	1	穿礼服的女人|女人|礼服	woman in tuxedo|formal|tuxedo|wedding|woman
👰	1	戴头纱的人|人|头纱|婚礼|戴头纱的新娘|新娘|结婚	person with veil|person|veil|wedding
👰‍♂️	1	戴头纱的男人|头纱|男人	man with veil|man|veil|wedding
👰‍♀️	1	戴头纱的女人|头纱|女人	woman with veil|bride|veil|wedding|woman
🤰	1	孕妇|女人|怀孕|怀孕的女人	pregnant woman|pregnant|woman
🫃	1	怀孕的男人|充满|吃撑|怀孕|男子|腹部|臃肿	pregnant man|belly|bloated|full|man|overeat|pregnant
🫄	1	怀孕的人|充满|吃撑|怀孕|腹部|臃肿	pregnant person|belly|bloated|full|overeat|person|pregnant|stuffed
🤱	1	母乳喂养|乳房|哺乳|喂奶|婴儿	breast-feeding|baby|breast|feeding|mom|mother|nursing|woman
👩‍🍼	1	哺乳的女人|人物|保姆|哺乳|喂养|女人|妈咪|妈妈|婴儿|宝宝|母亲|爱	woman feeding baby|baby|feed|feeding|mom|mother|nanny|newborn|nursing|woman
👨‍🍼	1	哺乳的男人|人物|保姆|哺乳|哺育|喂养|婴儿|宝宝|新生儿|爱|父亲|父子情|父爱|男人	man feeding baby|baby|dad|father|feed|feeding|man|nanny|newborn|nursing
🧑‍🍼	1	哺乳的人|人|人物|保姆|哺乳|哺育|喂养|婴儿|宝宝|新生儿	person feeding baby|baby|feed|feeding|nanny|newborn|nursing|parent
👼	1	小天使|儿童|天使|孩子	baby angel|angel|baby|church|face|fairy|fairytale|fantasy|tale
🎅	1	圣诞老人|圣诞|圣诞节|节日	santa claus|celebration|christmas|claus|fairy|fantasy|father|holiday|merry|santa|tale|xmas
🤶	1	圣诞奶奶|圣诞|圣诞节|节日	mrs. claus|celebration|christmas|claus|fairy|fantasy|holiday|merry|mother|mrs|santa|tale|xmas
🧑‍🎄	1	圣诞人|人|人物|圣诞|圣诞帽|圣诞快乐|圣诞老人|圣诞老公公|节日	mx claus|celebration|christmas|claus|fairy|fantasy|holiday|merry|mx|santa|tale|xmas
🦸	1	超级英雄|女英雄|女超人|好人|英雄|蝙蝠侠|超人|超能力	superhero|good|hero|superpower
🦸‍♂️	1	男超级英雄|好人|男人|英雄|超能力	man superhero|good|hero|man|superhero|superpower
🦸‍♀️	1	女超级英雄|女人|好人|英雄|超能力	woman superhero|good|hero|heroine|superhero|superpower|woman
🦹	1	超级大坏蛋|人|坏蛋|大反派|恶魔|罪犯|超级恶棍|超能力|邪恶	supervillain|bad|criminal|evil|superpower|villain
🦹‍♂️	1	男超级大坏蛋|坏蛋|男人|罪犯|超能力	man supervillain|bad|criminal|evil|man|superpower|supervillain|villain
🦹‍♀️	1	女超级大坏蛋|坏蛋|女人|罪犯|超能力	woman supervillain|bad|criminal|evil|superpower|supervillain|villain|woman
🧙	1	法师|召唤|女巫|女魔术师|巫师|智者|法术|男巫|男魔术师|魔咒|魔术师	mage|fantasy|magic|play|sorcerer|sorceress|sorcery|spell|summon|witch|wizard
🧙‍♂️	1	男法师|男巫|男魔术师	man mage|fantasy|mage|magic|man|play|sorcerer|sorceress|sorcery|spell|summon|witch|wizard
🧙‍♀️	1	女法师|女巫|女魔术师	woman mage|fantasy|mage|magic|play|sorcerer|sorceress|sorcery|spell|summon|witch|wizard|woman
🧚	1	精灵|仙女|仙子|童话|翅膀	fairy|fairytale|fantasy|myth|person|pixie|tale|wings
🧚‍♂️	1	仙人|仙男|天卫十五|天卫四|男精灵	man fairy|fairy|fairytale|fantasy|man|myth|oberon|person|pixie|puck|tale|wings
🧚‍♀️	1	仙女|女精灵|妖精王后	woman fairy|fairy|fairytale|fantasy|myth|person|pixie|tale|titania|wings|woman
🧛	1	吸血鬼|万圣节|不死族|利牙|恐怖|毒牙|装扮服装|超自然	vampire|blood|dracula|fangs|halloween|scary|supernatural|teeth|undead
🧛‍♂️	1	男吸血鬼|男不死族	man vampire|blood|fangs|halloween|man|scary|supernatural|teeth|undead|vampire
🧛‍♀️	1	女吸血鬼|女不死族	woman vampire|blood|fangs|halloween|scary|supernatural|teeth|undead|vampire|woman
🧜	1	人鱼|三叉戟|女人鱼|民间传说|海妖|海底|海洋生物|男人鱼|童话|美人鱼	merperson|creature|fairytale|folklore|ocean|sea|siren|trident
🧜‍♂️	1	男人鱼|特里同	merman|creature|fairytale|folklore|neptune|ocean|poseidon|sea|siren|trident|triton
🧜‍♀️	1	美人鱼|女人鱼	mermaid|creature|fairytale|folklore|merwoman|ocean|sea|siren|trident
🧝	1	小精灵|神秘|精灵|魔幻|魔法	elf|elves|enchantment|fantasy|folklore|magic|magical|myth
🧝‍♂️	1	男小精灵|男性魔术	man elf|elf|elves|enchantment|fantasy|folklore|magic|magical|man|myth
🧝‍♀️	1	女小精灵|女性魔术	woman elf|elf|elves|enchantment|fantasy|folklore|magic|magical|myth|woman
🧞	0	妖怪|奇幻|愿望|擦拭神灯|杰尼|灯神|神灵|神秘|神话|精灵|镇尼	genie|djinn|fantasy|jinn|lamp|myth|rub|wishes
🧞‍♂️	0	男妖怪|男神灵	man genie|djinn|fantasy|genie|jinn|lamp|man|myth|rub|wishes
🧞‍♀️	0	女妖怪|女神灵	woman genie|djinn|fantasy|genie|jinn|lamp|myth|rub|wishes|woman
🧟	0	僵尸|万圣节|不死族|半死不活|吓人|行尸走肉	zombie|apocalypse|dead|halloween|horror|scary|undead|walking
🧟‍♂️	0	男僵尸|男行尸走肉	man zombie|apocalypse|dead|halloween|horror|man|scary|undead|walking|zombie
🧟‍♀️	0	女僵尸|女行尸走肉	woman zombie|apocalypse|dead|halloween|horror|scary|undead|walking|woman|zombie
🧌	0	穴居巨怪|幻想|怪兽|怪物|神话故事	troll|fairy|fantasy|monster|tale|trolling
💆	1	按摩|享受按摩的人|头痛|放松|水疗|治疗|紧张|缓解|美容|美容沙龙|面部	person getting massage|face|getting|headache|massage|person|relax|relaxing|salon|soothe|spa|tension|therapy|treatment
💆‍♂️	1	男生按摩|头痛|按摩|男|脸	man getting massage|face|getting|headache|man|massage|relax|relaxing|salon|soothe|spa|tension|therapy|treatment
💆‍♀️	1	女生按摩|女|按摩	woman getting massage|face|getting|headache|massage|relax|relaxing|salon|soothe|spa|tension|therapy|treatment|woman
💇	1	理发|剪头|发型|理发师|理发的人|美发|美容|美容沙龙|美容院|造型师	person getting haircut|barber|beauty|chop|cosmetology|cut|groom|hair|haircut|parlor|person|shears|style
💇‍♂️	1	男生理发|剪头|理发|男	man getting haircut|barber|beauty|chop|cosmetology|cut|groom|hair|haircut|man|parlor|person|shears|style
💇‍♀️	1	女生理发|剪头|女|理发	woman getting haircut|barber|beauty|chop|cosmetology|cut|groom|hair|haircut|parlor|person|shears|style|woman
🚶	1	行人|压马路|徒步|散步|昂首阔步|竞走|行走的人|走路|远足|闲逛	person walking|amble|gait|hike|man|pace|pedestrian|person|stride|stroll|walk|walking
🚶‍♂️	1	男行人|徒步|男|走路	man walking|amble|gait|hike|man|pace|pedestrian|stride|stroll|walk|walking
🚶‍♀️	1	女行人|女|徒步|漫步|缓行|走|走路|路人	woman walking|amble|gait|hike|man|pace|pedestrian|stride|stroll|walk|walking|woman
🧍	1	站立者|人物|站着|站着的人|站立	person standing|person|stand|standing
🧍‍♂️	1	站立的男人|男|站着|站立	man standing|man|stand|standing
🧍‍♀️	1	站立的女人|女|站着|站立	woman standing|stand|standing|woman
🧎	1	下跪者|下跪|跪下|跪坐	person kneeling|kneel|kneeling|knees|person
🧎‍♂️	1	跪下的男人|下跪|男|跪坐	man kneeling|kneel|kneeling|knees|man
🧎‍♀️	1	跪下的女人|下跪|女|跪坐	woman kneeling|kneel|kneeling|knees|woman
🧑‍🦯	1	拄盲杖的人|无障碍|盲	person with white cane|accessibility|blind|cane|person|probing|white
👨‍🦯	1	拄盲杖的男人|拐杖|无障碍|男|男人|男子|盲|盲人	man with white cane|accessibility|blind|cane|man|probing|white
👩‍🦯	1	拄盲杖的女人|女|女人|女性|拐杖|无障碍|盲|盲人	woman with white cane|accessibility|blind|cane|probing|white|woman
🧑‍🦼	1	坐电动轮椅的人|无障碍|轮椅	person in motorized wheelchair|accessibility|motorized|person|wheelchair
👨‍🦼	1	坐电动轮椅的男人|无障碍|电动|男|男人|男子|轮椅	man in motorized wheelchair|accessibility|man|motorized|wheelchair
👩‍🦼	1	坐电动轮椅的女人|女|女人|女子|无障碍|电动|轮椅	woman in motorized wheelchair|accessibility|motorized|wheelchair|woman
🧑‍🦽	1	坐手动轮椅的人|无障碍|轮椅	person in manual wheelchair|accessibility|manual|person|wheelchair
👨‍🦽	1	坐手动轮椅的男人|手动|无障碍|男|男人|男子|轮椅	man in manual wheelchair|accessibility|man|manual|wheelchair
👩‍🦽	1	坐手动轮椅的女人|女|女人|女子|手动|无障碍|轮椅	woman in manual wheelchair|accessibility|manual|wheelchair|woman
🏃	1	跑步者|匆忙|向前冲|奔跑|快跑|赛跑|跑步|跑路|闪人|马拉松	person running|fast|hurry|marathon|move|person|quick|race|racing|run|rush|speed
🏃‍♂️	1	男生跑步|男|跑|马拉松	man running|fast|hurry|man|marathon|move|quick|race|racing|run|rush|speed
🏃‍♀️	1	女生跑步|冲刺|女|比赛|跑|跑步|马拉松	woman running|fast|hurry|marathon|move|quick|race|racing|run|rush|speed|woman
💃	1	跳舞的女人|优雅|佛拉门戈|女人|女舞者|探戈|舞者|萨尔萨舞|跳舞	woman dancing|dance|dancer|dancing|elegant|festive|flair|flamenco|groove|let’s|salsa|tango|woman
🕺	1	跳舞的男人|佛拉门戈|男人|男舞者|舞者|跳舞	man dancing|dance|dancer|dancing|elegant|festive|flair|flamenco|groove|let’s|man|salsa|tango
🕴️	1	西装革履的人|商务|正装|男|西装革履	person in suit levitating|business|levitating|person|suit
👯	0	戴兔耳朵的人|兔子服|兔耳朵|双人舞|双胞胎|同好|永远的好朋友|派对|灵魂伴侣|聚会|舞者|跳舞|闺蜜	people with bunny ears|bestie|bff|bunny|counterpart|dancer|double|ear|identical|pair|party|partying|people|soulmate|twin|twinsies
👯‍♂️	0	兔先生|兔耳朵|同好|永远的好朋友|派对|男生派对|聚会|跳舞	men with bunny ears|bestie|bff|bunny|counterpart|dancer|double|ear|identical|men|pair|party|partying|people|soulmate|twin|twinsies
👯‍♀️	0	兔女郎|兔耳朵|女生派对|派对|聚会|跳舞	women with bunny ears|bestie|bff|bunny|counterpart|dancer|double|ear|identical|pair|party|partying|people|soulmate|twin|twinsies|women
🧖	1	蒸房里的人|在桑拿间的人|放松|桑拿|桑拿浴|蒸房|蒸气漫溢|蒸汽浴	person in steamy room|day|luxurious|pamper|person|relax|room|sauna|spa|steam|steambath|unwind
🧖‍♂️	1	蒸房里的男人|桑拿|男性桑拿	man in steamy room|day|luxurious|man|pamper|relax|room|sauna|spa|steam|steambath|unwind
🧖‍♀️	1	蒸房里的女人|女性桑拿|桑拿	woman in steamy room|day|luxurious|pamper|relax|room|sauna|spa|steam|steambath|unwind|woman
🧗	1	攀爬的人|向上爬的人|攀岩|攀岩者|爬山|登山|登山者	person climbing|climb|climber|climbing|mountain|person|rock|scale|up
🧗‍♂️	1	攀爬的男人|登山者	man climbing|climb|climber|climbing|man|mountain|rock|scale|up
🧗‍♀️	1	攀爬的女人|登山者	woman climbing|climb|climber|climbing|mountain|rock|scale|up|woman
🤺	0	击剑选手|人|体育|击剑|剑	person fencing|fencer|fencing|person|sword
🏇	1	赛马|三冠|赛马骑师|马|骑师|骑马	horse racing|horse|jockey|racehorse|racing|riding|sport
⛷️	0	滑雪的人|滑雪|雪	skier|ski|snow
🏂	1	滑雪板|单板|单板滑雪|滑雪|雪	snowboarder|ski|snow|snowboard|sport
🏌️	1	打高尔夫的人|pga|小鸟球|推杆进球|球|球座|球穴区|球童|职业高尔夫协会|运动|高尔夫	person golfing|ball|birdie|caddy|driving|golf|golfing|green|person|pga|putt|range|tee
🏌️‍♂️	1	男生打高尔夫|男|高尔夫	man golfing|ball|birdie|caddy|driving|golf|golfing|green|man|pga|putt|range|tee
🏌️‍♀️	1	女生打高尔夫|女|高尔夫|高尔夫练球场	woman golfing|ball|birdie|caddy|driving|golf|golfing|green|pga|putt|range|tee|woman
🏄	1	冲浪|冲浪的人|冲浪者|波浪|海上运动|海洋|海滩|涌浪|网上冲浪|运动	person surfing|beach|ocean|person|sport|surf|surfer|surfing|swell|waves
🏄‍♂️	1	男生冲浪|冲浪|男	man surfing|beach|man|ocean|sport|surf|surfer|surfing|swell|waves
🏄‍♀️	1	女生冲浪|冲浪|女|海滩	woman surfing|beach|ocean|person|sport|surf|surfer|surfing|swell|waves
🚣	1	划艇|划桨|划船运动|木筏|河|泛舟湖上|湖|独木舟|船|钓鱼	person rowing boat|boat|canoe|cruise|fishing|lake|oar|paddle|person|raft|river|row|rowboat|rowing
🚣‍♂️	1	男生划船|划船|划艇|男|船	man rowing boat|boat|canoe|cruise|fishing|lake|man|oar|paddle|raft|river|row|rowboat|rowing
🚣‍♀️	1	女生划船|划船|划艇|女|船	woman rowing boat|boat|canoe|cruise|fishing|lake|oar|paddle|raft|river|row|rowboat|rowing|woman
🏊	1	游泳|游泳的人|游泳者|自由泳|运动|铁人三项	person swimming|freestyle|person|sport|swim|swimmer|swimming|triathlon
🏊‍♂️	1	男生游泳|游泳|男	man swimming|freestyle|man|sport|swim|swimmer|swimming|triathlon
🏊‍♀️	1	女生游泳|女|游泳	woman swimming|freestyle|man|sport|swim|swimmer|swimming|triathlon
⛹️	1	玩球|体育|全网无阻|打球|游戏|玩|球|篮球|篮球运动员|罚球|运动|运球|锦标赛	person bouncing ball|athletic|ball|basketball|bouncing|championship|dribble|net|person|player|throw
⛹️‍♂️	1	男生玩球|球|男	man bouncing ball|athletic|ball|basketball|bouncing|championship|dribble|man|net|player|throw
⛹️‍♀️	1	女生玩球|女|女生打篮球|游戏|玩|球|篮球	woman bouncing ball|athletic|ball|basketball|bouncing|championship|dribble|net|player|throw|woman
🏋️	1	举重|举重的人|举重运动员|举铁|健美者|力量举重|杠铃|硬拉|训练|运动	person lifting weights|barbell|bodybuilder|deadlift|lifter|lifting|person|powerlifting|weight|weightlifter|weights|workout
🏋️‍♂️	1	男生举重|举重|男	man lifting weights|barbell|bodybuilder|deadlift|lifter|lifting|man|powerlifting|weight|weightlifter|weights|workout
🏋️‍♀️	1	女生举重|举重|女|训练	woman lifting weights|barbell|bodybuilder|deadlift|lifter|lifting|powerlifting|weight|weightlifter|weights|woman|workout
🚴	1	骑自行车|单车|脚踏车|自行车|自行车赛|自行车骑士|运动|骑单车|骑脚踏车者|骑自行车的人|骑自行车者	person biking|bicycle|bicyclist|bike|biking|cycle|cyclist|person|riding|sport
🚴‍♂️	1	男生骑自行车|单车|男|自行车|骑车	man biking|bicycle|bicyclist|bike|biking|cycle|cyclist|man|riding|sport
🚴‍♀️	1	女生骑自行车|单车|女|女生骑车|自行车|骑车	woman biking|bicycle|bicyclist|bike|biking|cycle|cyclist|riding|sport|woman
🚵	1	骑山地车|体育竞技|单车|山|山地自行车|山地车|山地骑行的人|自行车|运动|骑山地车的人|骑自行车|骑自行车者	person mountain biking|bicycle|bicyclist|bike|biking|cycle|cyclist|mountain|person|riding|sport
🚵‍♂️	1	男生骑山地车|单车|山地车|男|自行车|骑山地车的人	man mountain biking|bicycle|bicyclist|bike|biking|cycle|cyclist|man|mountain|riding|sport
🚵‍♀️	1	女生骑山地车|单车|女|山地车|自行车|骑车	woman mountain biking|bicycle|bicyclist|bike|biking|cycle|cyclist|mountain|riding|sport|woman
🤸	1	侧手翻|人|体操|体育|兴奋|快乐|杂技|活泼|翻筋斗	person cartwheeling|active|cartwheel|cartwheeling|excited|flip|gymnastics|happy|person|somersault
🤸‍♂️	1	男生侧手翻|体操|侧手翻|兴奋|快乐|杂技|活泼|男|男子侧手翻|翻筋斗	man cartwheeling|active|cartwheel|cartwheeling|excited|flip|gymnastics|happy|man|somersault
🤸‍♀️	1	女生侧手翻|体操|侧手翻|兴奋|女|女子侧手翻|快乐|杂技|活泼|翻筋斗	woman cartwheeling|active|cartwheel|cartwheeling|excited|flip|gymnastics|happy|somersault|woman
🤼	0	摔跤选手|人|体育|对决|打架|搏斗|摔跤|摔跤比赛|擂台争霸|运动	people wrestling|combat|duel|grapple|people|ring|tournament|wrestle|wrestling
🤼‍♂️	0	男生摔跤|对决|打架|搏斗|摔跤|摔跤比赛|擂台争霸|男|男子摔跤|运动	men wrestling|combat|duel|grapple|men|ring|tournament|wrestle|wrestling
🤼‍♀️	0	女生摔跤|女|女子摔跤|对决|打架|搏斗|摔跤|摔跤比赛|擂台争霸|运动	women wrestling|combat|duel|grapple|ring|tournament|women|wrestle|wrestling
🤽	1	水球|人|体育|水上足球|水上运动|游泳|马可波罗游戏	person playing water polo|person|playing|polo|sport|swimming|water|waterpolo
🤽‍♂️	1	男生玩水球|水上足球|水上运动|水球|游泳|男|男子玩水球|马可波罗游戏	man playing water polo|man|playing|polo|sport|swimming|water|waterpolo
🤽‍♀️	1	女生玩水球|女|女子玩水球|水上足球|水上运动|水球|游泳|马可波罗游戏	woman playing water polo|playing|polo|sport|swimming|water|waterpolo|woman
🤾	1	手球|人|体育|投|投球|抛|接球|犯规投球|球|运动|高球	person playing handball|athletics|ball|catch|chuck|handball|hurl|lob|person|pitch|playing|sport|throw|toss
🤾‍♂️	1	男生玩手球|墙手球|手球|男	man playing handball|athletics|ball|catch|chuck|handball|hurl|lob|man|pitch|playing|sport|throw|toss
🤾‍♀️	1	女生玩手球|女|女子玩手球|手球|扔|投球|抛|接球|犯规投球|球|运动|高球	woman playing handball|athletics|ball|catch|chuck|handball|hurl|lob|pitch|playing|sport|throw|toss|woman
🤹	1	抛接杂耍|一心多用|人|平衡|平衡艺术|抛接|抛接球|操纵|杂技|杂耍|表演	person juggling|act|balance|balancing|handle|juggle|juggling|manage|multitask|person|skill
🤹‍♂️	1	男生抛接杂耍|一心多用|平衡艺术|抛接球|操纵|杂技|杂耍|男|男子|颠球	man juggling|act|balance|balancing|handle|juggle|juggling|man|manage|multitask|skill
🤹‍♀️	1	女生抛接杂耍|女|杂技|杂耍|颠球	woman juggling|act|balance|balancing|handle|juggle|juggling|manage|multitask|skill|woman
🧘	1	盘腿的人|冥想|放松|沉思|瑜伽|盘腿而坐|禅|莲花坐的人	person in lotus position|cross|legged|legs|lotus|meditation|peace|person|position|relax|serenity|yoga|yogi|zen
🧘‍♂️	1	盘腿的男人|和尚|瑜伽男	man in lotus position|cross|legged|legs|lotus|man|meditation|peace|position|relax|serenity|yoga|yogi|zen
🧘‍♀️	1	盘腿的女人|尼姑|比丘尼|瑜伽女	woman in lotus position|cross|legged|legs|lotus|meditation|peace|position|relax|serenity|woman|yoga|yogi|zen
🛀	1	洗澡的人|洗澡|浴盆|浴缸|澡盆|盆浴	person taking bath|bath|bathtub|person|taking|tub
🛌	1	躺在床上的人|入睡|夜里|宾馆|晚安|酒店	person in bed|bed|bedtime|good|goodnight|hotel|nap|night|person|sleep|tired|zzz
🧑‍🤝‍🧑	0	手拉手的两个人|两个人手牵手|人|情侣|手|手牵手的人|拉手|握手|牵手	people holding hands|bae|bestie|bff|couple|dating|flirt|friends|hand|hold|people|twins
👭	1	手拉手的两个女人|两个女人|好朋友|情侣|手拉手|朋友	women holding hands|bae|bestie|bff|couple|dating|flirt|friends|girls|hand|hold|sisters|twins|women
👫	1	手拉手的一男一女|一男一女|情侣|手拉手|相恋	woman and man holding hands|bae|bestie|bff|couple|dating|flirt|friends|hand|hold|man|twins|woman
👬	1	手拉手的两个男人|两个男人|双子座|情侣|手拉手|朋友|黄道十二宫	men holding hands|bae|bestie|bff|boys|brothers|couple|dating|flirt|friends|hand|hold|men|twins
💏	1	亲吻|宝贝|情侣|接吻|浪漫|约会	kiss|anniversary|babe|bae|couple|date|dating|heart|love|mwah|person|romance|together|xoxo
👩‍❤️‍💋‍👨	0	亲吻: 女人男人|亲吻|女人|宝贝|情侣|接吻|浪漫|男人|约会	kiss: woman, man|anniversary|babe|bae|couple|date|dating|heart|kiss|love|man|mwah|person|romance|together|woman|xoxo
👨‍❤️‍💋‍👨	0	亲吻: 男人男人|亲吻|宝贝|情侣|接吻|浪漫|男人|约会	kiss: man, man|anniversary|babe|bae|couple|date|dating|heart|kiss|love|man|mwah|person|romance|together|xoxo
👩‍❤️‍💋‍👩	0	亲吻: 女人女人|亲吻|女人|宝贝|情侣|接吻|浪漫|约会	kiss: woman, woman|anniversary|babe|bae|couple|date|dating|heart|kiss|love|mwah|person|romance|together|woman|xoxo
💑	1	情侣|恋爱|浪漫|红心|约会	couple with heart|anniversary|babe|bae|couple|dating|heart|kiss|love|person|relationship|romance|together|you
👩‍❤️‍👨	0	情侣: 女人男人|女人|恋爱|情侣|浪漫|男人|红心|约会	couple with heart: woman, man|anniversary|babe|bae|couple|dating|heart|kiss|love|man|person|relationship|romance|together|woman|you
👨‍❤️‍👨	0	情侣: 男人男人|恋爱|情侣|浪漫|男人|红心|约会	couple with heart: man, man|anniversary|babe|bae|couple|dating|heart|kiss|love|man|person|relationship|romance|together|you
👩‍❤️‍👩	0	情侣: 女人女人|女人|恋爱|情侣|浪漫|红心|约会	couple with heart: woman, woman|anniversary|babe|bae|couple|dating|heart|kiss|love|person|relationship|romance|together|woman|you
👨‍👩‍👦	0	家庭: 男人女人男孩|亲子|女人|家庭|父母和儿子|男人|男孩	family: man, woman, boy|boy|child|family|man|woman
👨‍👩‍👧	0	家庭: 男人女人女孩|亲子|女人|女孩|家庭|父母和儿子|男人	family: man, woman, girl|child|family|girl|man|woman
👨‍👩‍👧‍👦	0	家庭: 男人女人女孩男孩|亲子|女人|女孩|家庭|父母和儿子|男人|男孩	family: man, woman, girl, boy|boy|child|family|girl|man|woman
👨‍👩‍👦‍👦	0	家庭: 男人女人男孩男孩|亲子|女人|家庭|父母和儿子|男人|男孩	family: man, woman, boy, boy|boy|child|family|man|woman
👨‍👩‍👧‍👧	0	家庭: 男人女人女孩女孩|亲子|女人|女孩|家庭|父母和儿子|男人	family: man, woman, girl, girl|child|family|girl|man|woman
👨‍👨‍👦	0	家庭: 男人男人男孩|亲子|家庭|父母和儿子|男人|男孩	family: man, man, boy|boy|child|family|man
👨‍👨‍👧	0	家庭: 男人男人女孩|亲子|女孩|家庭|父母和儿子|男人	family: man, man, girl|child|family|girl|man
👨‍👨‍👧‍👦	0	家庭: 男人男人女孩男孩|亲子|女孩|家庭|父母和儿子|男人|男孩	family: man, man, girl, boy|boy|child|family|girl|man
👨‍👨‍👦‍👦	0	家庭: 男人男人男孩男孩|亲子|家庭|父母和儿子|男人|男孩	family: man, man, boy, boy|boy|child|family|man
👨‍👨‍👧‍👧	0	家庭: 男人男人女孩女孩|亲子|女孩|家庭|父母和儿子|男人	family: man, man, girl, girl|child|family|girl|man
👩‍👩‍👦	0	家庭: 女人女人男孩|亲子|女人|家庭|父母和儿子|男孩	family: woman, woman, boy|boy|child|family|woman
👩‍👩‍👧	0	家庭: 女人女人女孩|亲子|女人|女孩|家庭|父母和儿子	family: woman, woman, girl|child|family|girl|woman
👩‍👩‍👧‍👦	0	家庭: 女人女人女孩男孩|亲子|女人|女孩|家庭|父母和儿子|男孩	family: woman, woman, girl, boy|boy|child|family|girl|woman
👩‍👩‍👦‍👦	0	家庭: 女人女人男孩男孩|亲子|女人|家庭|父母和儿子|男孩	family: woman, woman, boy, boy|boy|child|family|woman
👩‍👩‍👧‍👧	0	家庭: 女人女人女孩女孩|亲子|女人|女孩|家庭|父母和儿子	family: woman, woman, girl, girl|child|family|girl|woman
👨‍👦	0	家庭: 男人男孩|亲子|家庭|父母和儿子|男人|男孩	family: man, boy|boy|child|family|man
👨‍👦‍👦	0	家庭: 男人男孩男孩|亲子|家庭|父母和儿子|男人|男孩	family: man, boy, boy|boy|child|family|man
👨‍👧	0	家庭: 男人女孩|亲子|女孩|家庭|父母和儿子|男人	family: man, girl|child|family|girl|man
👨‍👧‍👦	0	家庭: 男人女孩男孩|亲子|女孩|家庭|父母和儿子|男人|男孩	family: man, girl, boy|boy|child|family|girl|man
👨‍👧‍👧	0	家庭: 男人女孩女孩|亲子|女孩|家庭|父母和儿子|男人	family: man, girl, girl|child|family|girl|man
👩‍👦	0	家庭: 女人男孩|亲子|女人|家庭|父母和儿子|男孩	family: woman, boy|boy|child|family|woman
👩‍👦‍👦	0	家庭: 女人男孩男孩|亲子|女人|家庭|父母和儿子|男孩	family: woman, boy, boy|boy|child|family|woman
👩‍👧	0	家庭: 女人女孩|亲子|女人|女孩|家庭|父母和儿子	family: woman, girl|child|family|girl|woman
👩‍👧‍👦	0	家庭: 女人女孩男孩|亲子|女人|女孩|家庭|父母和儿子|男孩	family: woman, girl, boy|boy|child|family|girl|woman
👩‍👧‍👧	0	家庭: 女人女孩女孩|亲子|女人|女孩|家庭|父母和儿子	family: woman, girl, girl|child|family|girl|woman
🗣️	0	说话|剪影|头|脸|讲话|说话头	speaking head|face|head|silhouette|speak|speaking
👤	0	人像|剪影|半身|半身像	bust in silhouette|bust|mysterious|shadow|silhouette
👥	0	双人像|剪影|半身|半身像|朋友	busts in silhouette|bff|bust|busts|everyone|friend|friends|people|silhouette
🫂	0	人的拥抱|再见|友谊|告别|安慰|您好|感谢|抱抱|拥抱|爱	people hugging|comfort|embrace|farewell|friendship|goodbye|hello|hug|hugging|love|people|thanks
👪	0	家庭|亲子|父母和儿子	family|child
👣	0	脚印|在路上|赤脚|足迹	footprints|barefoot|clothing|footprint|omw|print|walk
🐵	0	猴头|动物|猴|猴子	monkey face|animal|banana|face|monkey
🐒	0	猴子|猴	monkey|animal|banana
🦍	0	大猩猩|动物	gorilla|animal
🦧	0	红毛猩猩|动物|猩猩|猴|猴子|猿	orangutan|animal|ape|monkey
🐶	0	狗脸|宠物|小狗|汪星人|狗|脸	dog face|adorbs|animal|dog|face|pet|puppies|puppy
🐕	0	狗|动物|宠物|小狗|汪星人	dog|animal|animals|dogs|pet
🦮	0	导盲犬|指引|无障碍|盲|盲人	guide dog|accessibility|animal|blind|dog|guide
🐕‍🦺	0	服务犬|工作犬|无障碍|服务|犬|狗|辅助	service dog|accessibility|animal|assistance|dog|service
🐩	0	贵宾犬|卷毛狗|毛茸茸|狗	poodle|animal|dog|fluffy
🐺	0	狼|头|狼头|脸	wolf|animal|face
🦊	0	狐狸|动物|头|狐狸的脸|脸	fox|animal|face
🦝	0	浣熊|动物|好奇|淘气|狡猾	raccoon|animal|curious|sly
🐱	0	猫脸|宠物|猫|猫咪|脸	cat face|animal|cat|face|kitten|kitty|pet
🐈	0	猫|宠物|小猫	cat|animal|animals|cats|kitten|pet
🐈‍⬛	0	黑猫|万圣节|不吉利|动物|喵|喵星人|猫|猫科|黑色	black cat|animal|black|cat|feline|halloween|meow|unlucky
🦁	0	狮子|狮子头|狮子座|脸|黄道十二宫	lion|alpha|animal|face|leo|mane|order|rawr|roar|safari|strong|zodiac
🐯	0	老虎头|森林之王|老虎|脸	tiger face|animal|big|cat|face|predator|tiger
🐅	0	老虎|动物园|虎	tiger|animal|big|cat|predator|zoo
🐆	0	豹子|动物|猎豹|豹	leopard|animal|big|cat|predator|zoo
🐴	0	马头|盛装舞步|马	horse face|animal|dressage|equine|face|farm|horse|horses
🫎	0	驼鹿|动物|哺乳动物|鹿角|麋鹿	moose|alces|animal|antlers|elk|mammal
🫏	0	驴|倔强|动物|哺乳动物|固执的|犟|驴子|骡|骡子	donkey|animal|ass|burro|hinny|mammal|mule|stubborn
🐎	0	马|动物|比赛|赛马|骑马	horse|animal|equestrian|farm|racehorse|racing
🦄	0	独角兽|头|独角兽头|脸	unicorn|face
🦓	0	斑马|条纹	zebra|animal|stripe
🦌	0	鹿|动物	deer|animal
🦬	0	大野牛|动物|欧洲野牛|水牛|牛|牦牛|畜群|野牛	bison|animal|buffalo|herd|wisent
🐮	0	奶牛头|乳牛|奶牛|母牛|牛头|脸	cow face|animal|cow|face|farm|milk|moo
🐂	0	公牛|牛|金牛座|黄道十二宫	ox|animal|animals|bull|farm|taurus|zodiac
🐃	0	水牛	water buffalo|animal|buffalo|water|zoo
🐄	0	奶牛|乳牛|牛	cow|animal|animals|farm|milk|moo
🐷	0	猪头|八戒|猪|脸	pig face|animal|bacon|face|farm|pig|pork
🐖	0	猪|培根|猪肉	pig|animal|bacon|farm|pork|sow
🐗	0	野猪|动物|猪	boar|animal|pig
🐽	0	猪鼻子|猪|脸|闻|鼻|鼻子	pig nose|animal|face|farm|nose|pig|smell|snout
🐏	0	公羊|白羊座|羊|雄性|黄道十二宫	ram|animal|aries|horns|male|sheep|zodiac|zoo
🐑	0	母羊|咩|毛茸茸|绵羊|羊|羊毛|雌性	ewe|animal|baa|farm|female|fluffy|lamb|sheep|wool
🐐	0	山羊|摩羯座|黄道十二宫	goat|animal|capricorn|farm|milk|zodiac
🐪	0	骆驼|单峰|单峰驼|沙漠|驼峰	camel|animal|desert|dromedary|hump|one
🐫	0	双峰骆驼|双峰|沙漠|骆驼	two-hump camel|animal|bactrian|camel|desert|hump|two|two-hump
🦙	0	美洲鸵|动物|原驼|小羊驼|无峰驼|羊毛|羊驼|骆马	llama|alpaca|animal|guanaco|vicuña|wool
🦒	0	长颈鹿|斑点	giraffe|animal|spots
🐘	0	大象|动物|象	elephant|animal
🦣	0	猛犸|动物|大型|有绒毛的|灭绝|猛犸象|长毛象|长牙	mammoth|animal|extinction|large|tusk|wooly
🦏	0	犀牛|动物	rhinoceros|animal
🦛	0	河马|动物	hippopotamus|animal|hippo
🐭	0	老鼠头|鼠	mouse face|animal|face|mouse
🐁	0	老鼠|耗子|鼠	mouse|animal|animals
🐀	0	耗子|鼠	rat|animal
🐹	0	仓鼠|仓鼠头|啮齿|头|宠物|脸	hamster|animal|face|pet
🐰	0	兔子头|兔|兔宝宝|宠物	rabbit face|animal|bunny|face|pet|rabbit
🐇	0	兔子|兔|动物	rabbit|animal|bunny|pet
🐿️	0	松鼠|花栗鼠|金花鼠	chipmunk|animal|squirrel
🦫	0	海狸|动物|大板牙|母畜	beaver|animal|dam|teeth
🦔	0	刺猬|多刺	hedgehog|animal|spiny
🦇	0	蝙蝠|吸血鬼	bat|animal|vampire
🐻	0	熊|低吼|头|灰熊|熊头|熊脸|脸	bear|animal|face|grizzly|growl|honey
🐻‍❄️	0	北极熊|北极|熊|白色	polar bear|animal|arctic|bear|polar|white
🐨	0	考拉|动物|有袋类动物|树袋熊|澳大利亚	koala|animal|australia|bear|down|face|marsupial|under
🐼	0	熊猫|头|熊猫脸|猫熊|猫熊脸|胖达|脸	panda|animal|bamboo|face
🦥	0	树懒|慢|懒|爬树|迟缓	sloth|lazy|slow
🦦	0	水獭|动物|好玩|捕鱼|爱开玩笑|獭|鼬	otter|animal|fishing|playful
🦨	0	臭鼬|熏|臭|鼬	skunk|animal|stink
🦘	0	袋鼠|动物|小袋鼠|有袋目动物|有袋类动物|澳洲|跳|跳跃	kangaroo|animal|joey|jump|marsupial
🦡	0	獾|动物|打扰|纠缠|蜜獾	badger|animal|honey|pester
🐾	0	爪印|爪|爪子|足迹	paw prints|feet|paw|paws|print|prints
🦃	0	火鸡|感恩节	turkey|bird|gobble|thanksgiving
🐔	0	鸡|动物	chicken|animal|bird|ornithology
🐓	0	公鸡|动物|鸡	rooster|animal|bird|ornithology
🐣	0	小鸡破壳|小鸡|破壳	hatching chick|animal|baby|bird|chick|egg|hatching
🐤	0	小鸡|鸡	baby chick|animal|baby|bird|chick|ornithology
🐥	0	正面朝向的小鸡|小鸡	front-facing baby chick|animal|baby|bird|chick|front-facing|newborn|ornithology
🐦	0	鸟|动物|鸟类学	bird|animal|ornithology
🐧	0	企鹅|南极|南极洲	penguin|animal|antarctica|bird|ornithology
🕊️	0	鸽|和平|和平象征|飞翔|鸟|鸽子	dove|bird|fly|ornithology|peace
🦅	0	鹰|老鹰|鸟	eagle|animal|bird|ornithology
🦆	0	鸭子|鸟|鸭	duck|animal|bird|ornithology
🦢	0	天鹅|丑小鸭|动物|小天鹅|鸟	swan|animal|bird|cygnet|duckling|ornithology|ugly
🦉	0	猫头鹰|睿智|鸟	owl|animal|bird|ornithology|wise
🦤	0	渡渡鸟|动物|灭绝|鸟	dodo|animal|bird|extinction|large|ornithology
🪶	0	羽毛|轻|飞|鸟	feather|bird|flight|light|plumage
🦩	0	火烈鸟|华丽|热带|红鹳|艳丽	flamingo|animal|bird|flamboyant|ornithology|tropical
🦚	0	孔雀|卖弄|招摇|色彩缤纷|雌孔雀|骄傲|鸟	peacock|animal|bird|colorful|ornithology|ostentatious|peahen|pretty|proud
🦜	0	鹦鹉|剽窃|模仿|说话|鸟	parrot|animal|bird|ornithology|pirate|talk
🪽	0	翅膀|升天|天使|天使的|天堂的|神话|翱翔|飞翔|飞行|鸟	wing|angelic|ascend|aviation|bird|fly|flying|heavenly|mythology|soar
🐦‍⬛	0	黑色的鸟|乌鸦|动物|喙|渡鸦|秃鼻乌鸦|老鸦|鸟|鸦叫声|鸦科|黑色	black bird|animal|beak|bird|black|caw|corvid|crow|ornithology|raven|rook
🪿	0	鹅|傻|傻瓜|动物|嘎嘎叫声|家禽|雄鹅|鸟|鸣叫|鸭子|鸭群|鹅群	goose|animal|bird|duck|flock|fowl|gaggle|gander|geese|honk|ornithology|silly
🐸	0	青蛙|动物|头|脸|青蛙头	frog|animal|face
🐊	0	鳄鱼	crocodile|animal|zoo
🐢	0	龟|乌龟|海龟|陆龟	turtle|animal|terrapin|tortoise
🦎	0	蜥蜴|爬行动物	lizard|animal|reptile
🐍	0	蛇|持票人|狡猾的人|蛇夫座|黄道十二宫	snake|animal|bearer|ophiuchus|serpent|zodiac
🐲	0	龙头|神话|童话|龙	dragon face|animal|dragon|face|fairy|fairytale|tale
🐉	0	龙|中国|权力的游戏	dragon|animal|fairy|fairytale|knights|tale
🦕	0	蜥蜴类|万龙属|恐龙|梁龙|腕龙|雷龙	sauropod|brachiosaurus|brontosaurus|dinosaur|diplodocus
🦖	0	霸王龙|恐龙|暴龙|暴龙君主	t-rex|dinosaur|rex|t|tyrannosaurus
🐳	0	喷水的鲸|喷水|鲸	spouting whale|animal|beach|face|ocean|spouting|whale
🐋	0	鲸鱼	whale|animal|beach|ocean
🐬	0	海豚|鸭脚板	dolphin|animal|beach|flipper|ocean
🦭	0	海豹|动物|海洋|海狮	seal|animal|lion|ocean|sea
🐟	0	鱼|双鱼座|星座|黄道十二宫	fish|animal|dinner|fishes|fishing|pisces|zodiac
🐠	0	热带鱼|热带|鱼	tropical fish|animal|fish|fishes|tropical
🐡	0	河豚|鱼	blowfish|animal|fish
🦈	0	鲨鱼|鱼|鲨	shark|animal|fish
🐙	0	章鱼|八爪|鱼	octopus|animal|creature|ocean
🐚	0	海螺|螺|螺旋	spiral shell|animal|beach|conch|sea|shell|spiral
🪸	0	珊瑚|气候变化|海洋|珊瑚礁|礁	coral|change|climate|ocean|reef|sea
🪼	0	水母|刺毛|动物|发光|哎哟|无脊椎动物|有刺动物|果冻|水族馆|浮游生物|海洋|海洋生物|海蜇|触手	jellyfish|animal|aquarium|burn|invertebrate|jelly|life|marine|ocean|ouch|plankton|sea|sting|stinger|tentacles
🐌	0	蜗牛|法国蜗牛	snail|animal|escargot|garden|nature|slug
🦋	0	蝴蝶|昆虫|漂亮|美丽	butterfly|insect|pretty
🐛	0	毛毛虫|昆虫|毛虫	bug|animal|garden|insect
🐜	0	蚂蚁	ant|animal|garden|insect
🐝	0	蜜蜂|勤劳|昆虫|蜂蜜	honeybee|animal|bee|bumblebee|honey|insect|nature|spring
🪲	0	甲虫|动物|昆虫|虫子	beetle|animal|bug|insect
🐞	0	瓢虫|昆虫|母	lady beetle|animal|beetle|garden|insect|lady|ladybird|ladybug|nature
🦗	0	蟋蟀|昆虫|蚱蜢|蛐蛐	cricket|animal|bug|grasshopper|insect|orthoptera
🪳	0	蟑螂|动物|害虫|小强|昆虫|虫子	cockroach|animal|insect|pest|roach
🕷️	0	蜘蛛|昆虫	spider|animal|insect
🕸️	0	蜘蛛网|蛛网|蜘蛛	spider web|spider|web
🦂	0	蝎子|天蝎宫|天蝎座|黄道十二宫	scorpion|scorpio|scorpius|zodiac
🦟	0	蚊子|发烧|发热|昆虫|疟疾|疾病|病|病毒	mosquito|bite|disease|fever|insect|malaria|pest|virus
🪰	0	苍蝇|动物|害虫|疾病|腐烂|虫子|蛆	fly|animal|disease|insect|maggot|pest|rotting
🪱	0	蠕虫|动物|寄生虫|环节动物|蚯蚓	worm|animal|annelid|earthworm|parasite
🦠	0	细菌|变形虫|病毒|科学|阿米巴	microbe|amoeba|bacteria|science|virus
💐	0	花束|周年纪念|生日|罗曼史|鲜花	bouquet|anniversary|birthday|date|flower|love|plant|romance
🌸	0	樱花|花	cherry blossom|blossom|cherry|flower|plant|spring|springtime
💮	0	白花|花	white flower|flower|white
🪷	0	莲花|佛教|印度教|幽静|恬静|纯洁|花|花朵	lotus|beauty|buddhism|calm|flower|hinduism|peace|purity|serenity
🏵️	0	圆形花饰|光荣花|植物|花|花圈	rosette|plant
🌹	0	玫瑰|优雅|红玫瑰|花	rose|beauty|elegant|flower|love|plant|red|valentine
🥀	0	枯萎的花|凋谢|枯萎|花	wilted flower|dying|flower|wilted
🌺	0	芙蓉|木槿|植物|花	hibiscus|flower|plant
🌻	0	向日葵|太阳|太阳花|花	sunflower|flower|outdoors|plant|sun
🌼	0	开花|花|蒲公英	blossom|buttercup|dandelion|flower|plant
🌷	0	郁金香|开花|花	tulip|blossom|flower|growth|plant
🪻	0	风信子|春天|植物|灌木|矢车菊|紫丁香|紫罗兰|紫色|羽扇豆|花|花朵|蓝帽花|薰衣草|金鱼草|靛蓝	hyacinth|bloom|bluebonnet|flower|indigo|lavender|lilac|lupine|plant|purple|shrub|snapdragon|spring|violet
🌱	0	幼苗|发芽|芽|苗	seedling|plant|sapling|sprout|young
🪴	0	盆栽植物|培育|房子|枯燥|植物|生长|盆景|盆栽|花盆	potted plant|decor|grow|house|nurturing|plant|pot|potted
🌲	0	松树|圣诞树|常青树|树	evergreen tree|christmas|evergreen|forest|pine|tree
🌳	0	落叶树|树|落叶|落叶植物	deciduous tree|deciduous|forest|green|habitat|shedding|tree
🌴	0	棕榈树|树|棕榈|热带	palm tree|beach|palm|plant|tree|tropical
🌵	0	仙人掌|干旱|植物|沙漠	cactus|desert|drought|nature|plant
🌾	0	稻子|稻|米|粮食|谷物	sheaf of rice|ear|grain|grains|plant|rice|sheaf
🌿	0	药草|草药|香草	herb|leaf|plant
☘️	0	三叶草|爱尔兰|苜蓿|酢浆草	shamrock|irish|plant
🍀	0	四叶草|幸运|爱尔兰的	four leaf clover|4|clover|four|four-leaf|irish|leaf|lucky|plant
🍁	0	枫叶|树叶|秋叶|落叶	maple leaf|falling|leaf|maple
🍂	0	落叶|叶|秋	fallen leaf|autumn|fall|fallen|falling|leaf
🍃	0	风吹叶落|叶子|树叶|随风飘舞	leaf fluttering in wind|blow|flutter|fluttering|leaf|wind
🪹	0	空巢|家|树枝|筑巢|鸟巢	empty nest|branch|empty|home|nest|nesting
🪺	0	有蛋的巢|树枝|筑巢|蛋|鸟|鸟巢|鸟蛋	nest with eggs|bird|branch|egg|eggs|nest|nesting
🍄	0	蘑菇|毒蕈|真菌	mushroom|fungus|toadstool
🍇	0	葡萄|水果	grapes|dionysus|fruit|grape
🍈	0	甜瓜|哈密瓜|水果|蜜瓜|香瓜	melon|cantaloupe|fruit
🍉	0	西瓜|水果	watermelon|fruit
🍊	0	橘子|柑桔|柑橘|桔子|水果|油桃|维他命 C	tangerine|c|citrus|fruit|nectarine|orange|vitamin
🍋	0	柠檬|柑橘|水果|酸	lemon|citrus|fruit|sour
🍌	0	香蕉|水果|钾	banana|fruit|potassium
🍍	0	菠萝|水果|热带	pineapple|colada|fruit|pina|tropical
🥭	0	芒果|水果|热带|食物	mango|food|fruit|tropical
🍎	0	红苹果|健康|水果|熟|红|苹果|食物	red apple|apple|diet|food|fruit|health|red|ripe
🍏	0	青苹果|水果|苹果|青	green apple|apple|fruit|green
🍐	0	梨|水果	pear|fruit
🍑	0	桃|水果	peach|fruit
🍒	0	樱桃|水果	cherries|berries|cherry|fruit|red
🍓	0	草莓|水果|浆果	strawberry|berry|fruit
🫐	0	蓝莓|水果|浆果|越桔|食物	blueberries|berries|berry|bilberry|blue|blueberry|food|fruit
🥝	0	猕猴桃|奇异果|水果|食物	kiwi fruit|food|fruit|kiwi
🍅	0	西红柿|水果|番茄|蔬菜	tomato|food|fruit|vegetable
🫒	0	橄榄|食物	olive|food
🥥	0	椰子|棕榈|菠萝椰子兰姆酒	coconut|colada|palm|piña
🥑	0	鳄梨|水果|牛油果|酪梨|食物|黄油果	avocado|food|fruit
🍆	0	茄子|蔬菜	eggplant|aubergine|vegetable
🥔	0	土豆|蔬菜|食物|马铃薯	potato|food|vegetable
🥕	0	胡萝卜|蔬菜|食物	carrot|food|vegetable
🌽	0	玉米|农作物|包谷|苞米	ear of corn|corn|crops|ear|farm|maize|maze
🌶️	0	红辣椒|辣|辣椒	hot pepper|hot|pepper
🫑	0	灯笼椒|蔬菜|辣椒|青椒|食物	bell pepper|bell|capsicum|food|pepper|vegetable
🥒	0	黄瓜|泡菜|腌菜|蔬菜|食物	cucumber|food|pickle|vegetable
🥬	0	绿叶蔬菜|卷心菜|圆白菜|小白菜|甘蓝|生菜|羽衣甘蓝|色拉|莴苣	leafy green|bok|burgers|cabbage|choy|green|kale|leafy|lettuce|salad
🥦	0	西兰花|甘蓝|野生卷心菜	broccoli|cabbage|wild
🧄	0	蒜|佐料|大蒜|蒜头|调味	garlic|flavoring
🧅	0	洋葱|佐料|调味	onion|flavoring
🥜	0	花生|坚果|蔬菜|食物	peanuts|food|nut|peanut|vegetable
🫘	0	豆|肾|豆子|豆类|食物	beans|food|kidney|legume|small
🌰	0	栗子|杏仁	chestnut|almond|plant
🫚	0	姜|健康|啤酒|天然|根|根汁啤酒|根茎|草药|香料	ginger root|beer|ginger|health|herb|natural|root|spice
🫛	0	豌豆荚|大豆|毛豆|素食者|荚|蔬菜|豆|豆类|豆茎|豆荚|豌豆|黄豆	pea pod|beans|beanstalk|edamame|legume|pea|pod|soybean|vegetable|veggie
🍞	0	面包|一条面包|全麦面包|小麦|淀粉|烤面包|谷类|食物|餐厅	bread|carbs|food|grain|loaf|restaurant|toast|wheat
🥐	0	羊角面包|新月形面包|法式|牛角面包|面包|食物	croissant|bread|breakfast|crescent|food|french|roll
🥖	0	法式长棍面包|法式|法式长条面包|面包|食物	baguette bread|baguette|bread|food|french
🫓	0	扁面包|圆盘状烤饼|玉米饼|皮塔饼|薄脆饼|面包|面饼|食物	flatbread|arepa|bread|food|gordita|lavash|naan|pita
🥨	0	椒盐卷饼|弯曲|扭曲食品|盘绕|缠绕|错综复杂	pretzel|convoluted|twisted
🥯	0	面包圈|奶酪酱|早餐|烘烤食品|硬面包圈|贝果|面包	bagel|bakery|bread|breakfast|schmear
🥞	0	烙饼|煎饼|薄煎饼|薄饼|食物	pancakes|breakfast|crêpe|food|hotcake|pancake
🧇	0	华夫饼|松饼|格子饼|点心|烤|甜点|窝夫饼	waffle|breakfast|indecisive|iron
🧀	0	芝士|奶酪|起司	cheese wedge|cheese|wedge
🍖	0	排骨|带骨的肉|肉|骨	meat on bone|bone|meat
🍗	0	家禽的腿|家禽|火鸡|饿|骨|鸡肉|鸡腿	poultry leg|bone|chicken|drumstick|hungry|leg|poultry|turkey
🥩	0	肉块|排骨|牛排|猪排|红肉|羊排|肉|肉排	cut of meat|chop|cut|lambchop|meat|porkchop|red|steak
🥓	0	培根|烟肉|熏肉|肉|背肯|食物	bacon|breakfast|food|meat
🍔	0	汉堡|吃|汉堡包|速食|食物|饿	hamburger|burger|eat|fast|food|hungry
🍟	0	薯条|快餐|油炸|食物	french fries|fast|food|french|fries
🍕	0	披萨|一片比萨|比萨|比萨饼|起司|辣味香肠|食物|饿	pizza|cheese|food|hungry|pepperoni|slice
🌭	0	热狗|香肠	hot dog|dog|frankfurter|hot|hotdog|sausage
🥪	0	三明治|面包	sandwich|bread
🌮	0	墨西哥卷饼|卷饼|玉米卷饼|墨西哥|墨西哥玉米卷	taco|mexican
🌯	0	墨西哥玉米煎饼|卷饼|玉米煎饼|墨西哥|墨西哥卷饼	burrito|mexican|wrap
🫔	0	墨西哥粽子|巴西粽|粽子|食物|墨西哥|墨西哥饼	tamale|food|mexican|pamonha|wrapped
🥙	0	夹心饼|大饼|夹心|沙拉三明治|炸豆丸子|烤肉串|肉夹馍|食物	stuffed flatbread|falafel|flatbread|food|gyro|kebab|stuffed
🧆	0	炸豆丸子|中东蔬菜球|油炸鹰嘴豆饼|肉丸|鹰嘴豆	falafel|chickpea|meatball
🥚	0	蛋|食物	egg|breakfast|food
🍳	0	煎蛋|一面老一面嫩的煎蛋|做菜|只煎一面老|平底锅|早餐|煎|蛋|食堂	cooking|breakfast|easy|egg|fry|frying|over|pan|restaurant|side|sunny|up
🥘	0	装有食物的浅底锅|平底锅|浅底|炖菜|炖锅|煎锅|西班牙海鲜饭|食物	shallow pan of food|casserole|food|paella|pan|shallow
🍲	0	一锅食物|炖菜|锅|食物	pot of food|food|pot|soup|stew
🫕	0	奶酪火锅|奶酪|奶酪锅|巧克力|火锅|煮|煲汤|瑞士|融化|锅|食物	fondue|cheese|chocolate|food|melted|pot|ski
🥣	0	碗勺|早餐|燕麦|燕麦粥|碗中汤匙|碗和汤匙|稀饭|粥|谷物	bowl with spoon|bowl|breakfast|cereal|congee|oatmeal|porridge|spoon
🥗	0	绿色沙拉|沙拉|绿色蔬菜|食物	green salad|food|green|salad
🍿	0	爆米花|看电影	popcorn|corn|movie|pop
🧈	0	黄油|乳制品|牛奶	butter|dairy
🧂	0	盐|佐料瓶|味道|咸|火大|调味品|调味料	salt|condiment|flavor|mad|salty|shaker|taste|upset
🥫	0	罐头食品|罐头	canned food|can|canned|food
🍱	0	盒饭|便当|便当盒|食物	bento box|bento|box|food
🍘	0	米饼|米|米果|食物	rice cracker|cracker|food|rice
🍙	0	饭团|日式饭团|日本|米|食物	rice ball|ball|food|japanese|rice
🍚	0	米饭|主食|米|食物|饭	cooked rice|cooked|food|rice
🍛	0	咖喱饭|咖喱|食物|饭	curry rice|curry|food|rice
🍜	0	面条|拉面|河粉|热气腾腾|热气腾腾面碗|碗|筷子|食物	steaming bowl|bowl|chopsticks|food|noodle|pho|ramen|soup|steaming
🍝	0	意粉|意大利面|意面|肉丸|食物|餐厅	spaghetti|food|meatballs|pasta|restaurant
🍠	0	烤红薯|地瓜|烤地瓜|红薯|食物	roasted sweet potato|food|potato|roasted|sweet
🍢	0	关东煮|串|卡博|海鲜|食物|餐馆	oden|food|kebab|restaurant|seafood|skewer|stick
🍣	0	寿司|食物	sushi|food
🍤	0	天妇罗|对虾|油炸|炸虾|虾	fried shrimp|fried|prawn|shrimp|tempura
🍥	0	鱼板|鱼|鱼饼	fish cake with swirl|cake|fish|food|pastry|restaurant|swirl
🥮	0	月饼|中秋节|秋|秋天|节日	moon cake|autumn|cake|festival|moon|yuèbǐng
🍡	0	团子|串|和果子|日本|甜点|糖葫芦	dango|dessert|japanese|skewer|stick|sweet
🥟	0	饺子|恩潘纳达|水饺|波兰饺子|煎饺	dumpling|empanada|gyōza|jiaozi|pierogi|potsticker
🥠	0	幸运饼干|签餅|算命|预言	fortune cookie|cookie|fortune|prophecy
🥡	0	外卖盒|中式外卖|外卖|外卖包装|外卖桶|外卖餐盒|牡蛎桶|盒饭|筷子|送餐|送餐服务	takeout box|box|chopsticks|delivery|food|oyster|pail|takeout
🦀	0	蟹|巨蟹座|螃蟹|黄道十二宫	crab|cancer|zodiac
🦞	0	龙虾|浓汤|海鲜|红龙虾|贝类浓汤|钳|鳌	lobster|animal|bisque|claws|seafood
🦐	0	虾|甲壳|贝类水产|食物	shrimp|food|shellfish|small
🦑	0	乌贼|软体动物|食物|鱿鱼|墨鱼	squid|animal|food|mollusk
🦪	0	牡蛎|海鲜|珍珠|生蚝	oyster|diving|pearl
🍦	0	圆筒冰激凌|冰淇淋|圆筒冰淇淋|甜|甜点|霜淇淋|食物	soft ice cream|cream|dessert|food|ice|icecream|restaurant|serve|soft|sweet
🍧	0	刨冰|冰|冰沙|沙冰|甜|甜点|餐馆	shaved ice|dessert|ice|restaurant|shaved|sweet
🍨	0	冰淇淋|冰|冰激凌|奶油|甜|甜点|雪糕	ice cream|cream|dessert|food|ice|restaurant|sweet
🍩	0	甜甜圈|甜|甜点|食物	doughnut|breakfast|dessert|donut|food|sweet
🍪	0	饼干|巧克力片|曲奇|曲奇饼|甜点	cookie|chip|chocolate|dessert|sweet
🎂	0	生日蛋糕|庆祝|甜|甜点|生日|生日快乐|糕点|蛋糕	birthday cake|bday|birthday|cake|celebration|dessert|happy|pastry|sweet
🍰	0	水果蛋糕|一片蛋糕|奶油|奶油酥饼|甜点|糕点|蛋糕	shortcake|cake|dessert|pastry|slice|sweet
🧁	0	纸杯蛋糕|烘焙食品|甜点|请客|面包店	cupcake|bakery|dessert|sprinkles|sugar|sweet|treat
🥧	0	派|一片派|南瓜派|水果派|油酥点心|糕点|肉排|苹果派|馅	pie|apple|filling|fruit|meat|pastry|pumpkin|slice
🍫	0	巧克力|万圣节|巧克力棒|甜|甜品|甜点|糖果	chocolate bar|bar|candy|chocolate|dessert|halloween|sweet|tooth
🍬	0	糖|万圣节|嗜甜食|爱吃甜食|甜|甜点|糖果|糖果纸|蛀牙|餐馆	candy|cavities|dessert|halloween|restaurant|sweet|tooth|wrapper
🍭	0	棒棒糖|果子|甜|糖|糖果	lollipop|candy|dessert|food|restaurant|sweet
🍮	0	奶黄|卡士达|甜点|蛋奶冻|蛋奶沙司	custard|dessert|pudding|sweet
🍯	0	蜂蜜|小熊维尼|桶|甜|蜜罐	honey pot|barrel|bear|food|honey|honeypot|jar|pot|sweet
🍼	0	奶瓶|奶|婴儿|新生儿	baby bottle|babies|baby|birth|born|bottle|drink|infant|milk|newborn
🥛	0	一杯奶|喝|奶|杯|牛奶	glass of milk|drink|glass|milk
☕	0	热饮|咖啡|早晨|星巴克|热气腾腾|茶|饮料	hot beverage|beverage|cafe|caffeine|chai|coffee|drink|hot|morning|steaming|tea
🫖	0	茶壶|冲泡|壶|茶|食物	teapot|brew|drink|food|pot|tea
🍵	0	热茶|乌龙茶|无柄茶杯|杯|没有把手的茶杯|热饮|茶|茶杯|饮料	teacup without handle|beverage|cup|drink|handle|oolong|tea|teacup
🍶	0	清酒|喝酒|清酒杯|清酒瓶|瓶|酒|酒吧|酒杯|饮料	sake|bar|beverage|bottle|cup|drink|restaurant
🍾	0	开香槟|喝酒|庆祝|木塞|瓶子|砰|砰木塞的瓶子|香槟	bottle with popping cork|bar|bottle|cork|drink|popping
🍷	0	葡萄酒|俱乐部|喝酒|酒|酒吧|酒杯|饮料	wine glass|alcohol|bar|beverage|booze|club|drink|drinking|drinks|glass|restaurant|wine
🍸	0	鸡尾酒|俱乐部|喝酒|杯|玻璃杯|酒|酒吧|马丁尼|鸡尾酒杯	cocktail glass|alcohol|bar|booze|club|cocktail|drink|drinking|drinks|glass|mad|martini|men
🍹	0	热带水果饮料|俱乐部|喝酒|热带饮料|酒|酒吧|饮料|鸡尾酒	tropical drink|alcohol|bar|booze|club|cocktail|drink|drinking|drinks|drunk|mai|party|tai|tropical|tropics
🍺	0	啤酒|啤酒节|喝酒|杯|酒|酒吧	beer mug|alcohol|ale|bar|beer|booze|drink|drinking|drinks|mug|octoberfest|oktoberfest|pint|stein|summer
🍻	0	干杯|啤酒|喝酒|碰杯|酒|酒吧	clinking beer mugs|alcohol|bar|beer|booze|bottoms|cheers|clink|clinking|drinking|drinks|mugs
🥂	0	碰杯|喝|干杯|庆祝|杯	clinking glasses|celebrate|clink|clinking|drink|glass|glasses
🥃	0	平底杯|一杯威士忌|威士忌|平底无脚杯|杯|玻璃杯|酒|随行杯	tumbler glass|glass|liquor|scotch|shot|tumbler|whiskey|whisky
🫗	0	倾倒液体|倒出|倾倒|洒出|流出|玻璃杯|碰倒|空|饮料	pouring liquid|accident|drink|empty|glass|liquid|oops|pour|pouring|spill|water
🥤	0	带吸管杯|带吸管的杯子|果汁|水|汽水|苏打|苏打饮料|软饮料|麦乳精饮料	cup with straw|cup|drink|juice|malt|soda|soft|straw|water
🧋	0	珍珠奶茶|奶茶|泡泡|牛奶|珍珠|茶|茶饮|饮料	bubble tea|boba|bubble|food|milk|pearl|tea
🧃	0	饮料盒|吸管|果汁|果汁盒|甜味|盒装	beverage box|beverage|box|juice|straw|sweet
🧉	0	马黛茶|茶|饮料	mate|drink
🧊	0	冰块|冰|冰冷|冰山|冷|冷却|冷饮	ice|cold|cube|iceberg
🥢	0	筷子|箸	chopsticks|hashi|jeotgarak|kuaizi
🍽️	0	餐具|做菜|刀|刀叉与盘|叉|晚餐|烹饪|盘|西餐	fork and knife with plate|cooking|dinner|eat|fork|knife|plate
🍴	0	刀叉|中餐|刀|午餐|叉|吃|吃早餐|吃饭|好吃|早餐|晚餐|烹调|西餐|餐具|饿了	fork and knife|breakfast|breaky|cooking|cutlery|delicious|dinner|eat|feed|food|fork|hungry|knife|lunch|restaurant|yum|yummy
🥄	0	匙|勺|勺子|匙子|汤匙|调羹|餐具	spoon|eat|tableware
🔪	0	菜刀|主厨|刀|武器|烹饪	kitchen knife|chef|cooking|hocho|kitchen|knife|tool|weapon
🫙	0	罐|容器|瓶子|空|空瓶|调味品|贮藏|酱	jar|condiment|container|empty|nothing|sauce|store
🏺	0	双耳瓶|壶|水瓶|罐	amphora|aquarius|cooking|drink|jug|tool|weapon|zodiac
🌍	0	地球上的欧洲非洲|世界|地球|欧洲|非洲	globe showing europe-africa|africa|earth|europe|europe-africa|globe|showing|world
🌎	0	地球上的美洲|世界|全球|地球|美洲	globe showing americas|americas|earth|globe|showing|world
🌏	0	地球上的亚洲澳洲|世界|亚洲|亚澳|全球|地球|地球上的亚洲|澳洲	globe showing asia-australia|asia|asia-australia|australia|earth|globe|showing|world
🌐	0	带经纬线的地球|世界|全球|地球|子午线|经纬|经线	globe with meridians|earth|globe|internet|meridians|web|world|worldwide
🗺️	0	世界地图|世界|地图	world map|map|world
🗾	0	日本地图|地图|日本	map of japan|japan|map
🧭	0	指南针|定向|导航|方向|磁性|罗盘	compass|direction|magnetic|navigation|orienteering
🏔️	0	雪山|冷|山|泠|雪|雪封山头|雪顶	snow-capped mountain|cold|mountain|snow|snow-capped
⛰️	0	山|峰	mountain
🌋	0	火山|喷发|大自然|山|爆发	volcano|eruption|mountain|nature
🗻	0	富士山|大自然|山	mount fuji|fuji|mount|mountain|nature
🏕️	0	露营|帐篷	camping
🏖️	0	沙滩伞|伞|有伞的海滩|沙滩|海滩|阳伞	beach with umbrella|beach|umbrella
🏜️	0	沙漠|荒漠	desert
🏝️	0	无人荒岛|岛|沙滩孤岛|沙漠|荒岛	desert island|desert|island
🏞️	0	国家公园|公园|自然|风景	national park|national|park
🏟️	0	体育馆|竞技场	stadium
🏛️	0	古典建筑|古典|古建筑	classical building|building|classical
🏗️	0	施工|兴建|建筑施工	building construction|building|construction|crane
🧱	0	砖|墙|砂浆|黏土	brick|bricks|clay|mortar|wall
🪨	0	岩石|固体|坚不可摧|巨石|石头	rock|boulder|heavy|solid|stone|tough
🪵	0	木头|原木|圆木|木材|木桩	wood|log|lumber|timber
🛖	0	小屋|圆屋|家|茅屋|蒙古包	hut|home|house|roundhouse|shelter|yurt
🏘️	0	房屋建筑|住宅|小区|房|房子	houses|house
🏚️	0	废墟|废屋|荒宅|荒废|鬼屋	derelict house|derelict|home|house
🏠	0	房子|住家|家|乡村家园|建筑|心之所在|房屋|郊区	house|building|country|heart|home|ranch|settle|simple|suburban|suburbia|where
🏡	0	别墅|住家|家|乡村家园|庭院|庭院居家|建筑|心之所在|房子|花园|郊区	house with garden|building|country|garden|heart|home|house|ranch|settle|simple|suburban|suburbia|where
🏢	0	办公楼|写字楼|建筑	office building|building|city|cubical|job|office
🏣	0	日本邮局|建筑|日本|邮便|邮局	japanese post office|building|japanese|office|post
🏤	0	邮局|建筑|欧洲|欧洲邮局	post office|building|european|office|post
🏥	0	医院|医生|医药|建筑|看病	hospital|building|doctor|medicine
🏦	0	银行|建筑	bank|building
🏨	0	酒店|建筑|旅馆	hotel|building
🏩	0	情人酒店|建筑|情人旅馆|情侣酒店|旅馆	love hotel|building|hotel|love
🏪	0	便利店|24 小时|商店|建筑	convenience store|24|building|convenience|hours|store
🏫	0	学校|建筑|教学楼	school|building
🏬	0	商场|建筑|百货公司|百货商城|百货商店	department store|building|department|store
🏭	0	工厂|建筑	factory|building
🏯	0	日本城堡|城堡|建筑|日本	japanese castle|building|castle|japanese
🏰	0	欧洲城堡|城堡|建筑|欧洲	castle|building|european
💒	0	婚礼|教堂|浪漫|结婚	wedding|chapel|hitched|nuptials|romance
🗼	0	东京塔|东京|塔	tokyo tower|tokyo|tower
🗽	0	自由女神像|塑像|纽约|自由|雕塑	statue of liberty|liberty|liberty|new|ny|nyc|statue|statue|york
⛪	0	教堂|基督|基督教|宗教|小教堂	church|bless|chapel|christian|cross|religion
🕌	0	清真寺|伊斯兰|宗教|穆斯林	mosque|islam|masjid|muslim|religion
🛕	0	印度寺庙|佛寺|佛教|寺庙|寺院|庙宇	hindu temple|hindu|temple
🕍	0	犹太教堂|会堂|宗教|犹太|犹太教	synagogue|jew|jewish|judaism|religion|temple
⛩️	0	神社|宗教|日本|神道教	shinto shrine|religion|shinto|shrine
🕋	0	克尔白|伊斯兰|天房|宗教|穆斯林	kaaba|hajj|islam|muslim|religion|umrah
⛲	0	喷泉	fountain
⛺	0	帐篷|露营	tent|camping
🌁	0	有雾|雾|霾	foggy|fog
🌃	0	夜晚|星空|晚上	night with stars|night|star|stars
🏙️	0	城市风光|城市|都市|都市景观|高楼大厦	cityscape|city
🌄	0	山顶日出|太阳|山|日出|早晨|清晨	sunrise over mountains|morning|mountains|over|sun|sunrise
🌅	0	日出|大自然|太阳|早晨|清晨	sunrise|morning|nature|sun
🌆	0	城市黄昏|城市|夜晚|日落|都市|黄昏	cityscape at dusk|at|building|city|cityscape|dusk|evening|landscape|sun|sunset
🌇	0	日落|夕阳	sunset|building|dusk|sun
🌉	0	夜幕下的桥|夜幕|晚上|桥	bridge at night|at|bridge|night
♨️	0	温泉|水|泉|热气腾腾|蒸汽	hot springs|hot|hotsprings|springs|steaming
🎠	0	旋转木马|木马|游乐园	carousel horse|carousel|entertainment|horse
🛝	0	游乐场滑梯|游乐园|游乐场|滑梯|玩|玩耍	playground slide|amusement|park|play|playground|playing|slide|sliding|theme
🎡	0	摩天轮|游乐园	ferris wheel|amusement|ferris|park|theme|wheel
🎢	0	过山车|游乐园	roller coaster|amusement|coaster|park|roller|theme
💈	0	理发店|旋转|柱|理发|理发师|理发店旋转彩柱	barber pole|barber|cut|fresh|haircut|pole|shave
🎪	0	马戏团帐篷|帐篷|马戏团	circus tent|circus|tent
🚂	0	蒸汽火车|守车|旅行|火车|火车头|蒸汽|蒸汽车头|铁路	locomotive|caboose|engine|railway|steam|train|trains|travel
🚃	0	轨道车|旅行|电车|铁路	railway car|car|electric|railway|train|tram|travel|trolleybus
🚄	0	高速列车|动车|新干线|火车|速度|高铁	high-speed train|high-speed|railway|shinkansen|speed|train
🚅	0	子弹头高速列车|动车|子弹列车|子弹头|新干线|火车|高速|高铁	bullet train|bullet|high-speed|nose|railway|shinkansen|speed|train|travel
🚆	0	火车|到站|呜呜|铁路	train|arrived|choo|railway
🚇	0	地铁|捷运	metro|subway|travel
🚈	0	轻轨|到站|单轨电车|火车	light rail|arrived|light|monorail|rail|railway
🚉	0	车站|地铁|捷运|火车|铁路	station|railway|train
🚊	0	路面电车|捷运|电车	tram|trolleybus
🚝	0	单轨|单轨电车|火车	monorail|vehicle
🚞	0	山区铁路|山区|山地铁路|火车|铁路	mountain railway|car|mountain|railway|trip
🚋	0	有轨电车|轨道	tram car|bus|car|tram|trolley|trolleybus
🚌	0	公交车|公交|公共汽车|大巴	bus|school|vehicle
🚍	0	迎面驶来的公交车|公交|公共汽车|大巴|迎面驶来	oncoming bus|bus|cars|oncoming
🚎	0	无轨电车|公共汽车|电车	trolleybus|bus|tram|trolley
🚐	0	小巴|公共汽车|开车|移动房车	minibus|bus|drive|van|vehicle
🚑	0	救护车|急救|车辆	ambulance|emergency|vehicle
🚒	0	消防车|救火车|火灾	fire engine|engine|fire|truck
🚓	0	警车|檀岛警騎|汽车|警察|巡逻	police car|5-0|car|cops|patrol|police
🚔	0	迎面驶来的警车|汽车|警察|警车	oncoming police car|car|oncoming|police
🚕	0	出租车|小黄|开车|汽车|的士|计程车	taxi|cab|cabbie|car|drive|vehicle|yellow
🚖	0	迎面驶来的出租车|优步|出租车|叫车|小黄|开车|的士	oncoming taxi|cab|cabbie|cars|drove|hail|oncoming|taxi|yellow
🚗	0	汽车|开车|轿车	automobile|car|driving|vehicle
🚘	0	迎面驶来的汽车|开车|汽车|轿车|迎面而来	oncoming automobile|automobile|car|cars|drove|oncoming|vehicle
🚙	0	运动型多用途车|SUV|休旅车|休闲车|开车|房车|汽车|车辆|轿车|驾驶	sport utility vehicle|car|drive|recreational|sport|sportutility|utility|vehicle
🛻	0	敞蓬小型载货卡车|交通工具|卡车|汽车|皮卡|车|载货	pickup truck|automobile|car|flatbed|pick-up|pickup|transportation|truck
🚚	0	货车|卡车|开车|送货	delivery truck|car|delivery|drive|truck|vehicle
🚛	0	铰接式货车|卡车|拖车|搬运|货车|铰接式卡车	articulated lorry|articulated|car|drive|lorry|move|semi|truck|vehicle
🚜	0	拖拉机	tractor|vehicle
🏎️	0	赛车|汽车|疾驰|跑车	racing car|car|racing|zoom
🏍️	0	摩托车|摩托|赛车	motorcycle|racing
🛵	0	小型摩托车|摩托车|踏板车	motor scooter|motor|scooter
🦽	0	手动轮椅|无障碍|轮椅	manual wheelchair|accessibility|manual|wheelchair
🦼	0	电动轮椅|无障碍|轮椅	motorized wheelchair|accessibility|motorized|wheelchair
🛺	0	三轮摩托车|三脚鸡|三蹦子|嘟嘟车|电动三轮车|自动人力车|黄包车	auto rickshaw|auto|rickshaw|tuk
🚲	0	自行车|单车|脚踏车|自行车骑士|飞驰|骑车|骑车疾驰	bicycle|bike|class|cycle|cycling|cyclist|gang|ride|spin|spinning
🛴	0	滑板车	kick scooter|kick|scooter
🛹	0	滑板|板|踩滑板	skateboard|board|skate|skater|wheels
🛼	0	四轮滑冰鞋|旱冰|溜冰|溜冰鞋|滑冰|轮式|运动	roller skate|blades|roller|skate|skates|sport
🚏	0	公交车站|公交站|公共汽车站	bus stop|bus|busstop|stop
🛣️	0	高速公路|公路	motorway|highway|road
🛤️	0	铁轨|火车|铁路	railway track|railway|track|train
🛢️	0	石油桶|桶|油桶|石油	oil drum|drum|oil
⛽	0	油泵|加油|加油站|柴油|燃料|燃油	fuel pump|diesel|fuel|fuelpump|gas|gasoline|pump|station
🛞	0	车轮|圆圈|汽车|车辆|转动|轮胎	wheel|car|circle|tire|turn|vehicle
🚨	0	警车灯|灯|紧急|警报|警灯|警示	police car light|alarm|alert|beacon|car|emergency|light|police|revolving|siren
🚥	0	横向的红绿灯|交通灯|信号灯|红绿灯	horizontal traffic light|horizontal|intersection|light|signal|stop|stoplight|traffic
🚦	0	纵向的红绿灯|交叉口|交通灯|信号灯|直的红绿灯|红绿灯	vertical traffic light|drove|intersection|light|signal|stop|stoplight|traffic|vertical
🛑	0	停止标志|停止|八角形|八边形|标志	stop sign|octagonal|sign|stop
🚧	0	路障|施工	construction|barrier
⚓	0	锚|停泊|工具|船	anchor|ship|tool
🛟	0	救生圈|安全|救援|救生|救生用具|游泳|漂浮	ring buoy|buoy|float|life|lifesaver|preserver|rescue|ring|safety|save|saver|swim
⛵	0	帆船|游艇|船|驾帆船	sailboat|boat|resort|sailing|sea|yacht
🛶	0	独木舟|船	canoe|boat
🚤	0	快艇|亿万富翁|船|豪华游艇	speedboat|billionaire|boat|lake|luxury|millionaire|summer|travel
🛳️	0	客轮|客船|旅客	passenger ship|passenger|ship
⛴️	0	渡轮|旅客|渡船|轮船	ferry|boat|passenger
🛥️	0	摩托艇|船	motor boat|boat|motor|motorboat
🚢	0	船|旅客|旅行	ship|boat|passenger|travel
✈️	0	飞机|喷气机|旅行|飞行	airplane|aeroplane|fly|flying|jet|plane|travel
🛩️	0	小型飞机|小飞机|飞机	small airplane|aeroplane|airplane|plane|small
🛫	0	航班起飞|值机|出境|报到|登机|离境|航班|起飞|飞机	airplane departure|aeroplane|airplane|check-in|departure|departures|plane
🛬	0	航班降落|到达|着陆|航班|降落|飞机	airplane arrival|aeroplane|airplane|arrival|arrivals|arriving|landing|plane
🪂	0	降落伞|帆伞|悬挂滑翔|滑翔|滑翔伞|跳伞	parachute|hang-glide|parasail|skydive
💺	0	座位|位子|椅子	seat|chair
🚁	0	直升机|旅行|直升飞机	helicopter|copter|roflcopter|travel|vehicle
🚟	0	空轨|悬挂|悬挂式单轨|空中轨道列车	suspension railway|railway|suspension
🚠	0	缆车|空中|索道	mountain cableway|cable|cableway|gondola|lift|mountain|ski
🚡	0	索道|空中|缆车	aerial tramway|aerial|cable|car|gondola|ropeway|tramway
🛰️	0	卫星|太空	satellite|space
🚀	0	火箭|发射|太空|旅行	rocket|launch|rockets|space|travel
🛸	0	飞碟|UFO|不明飞行物|外星人|外星球	flying saucer|aliens|extra|flying|saucer|terrestrial|ufo
🛎️	0	服务铃|行李员|酒店|铃	bellhop bell|bell|bellhop|hotel
🧳	0	行李箱|包装|手提箱|旅行|滚轮提箱|行李	luggage|bag|packing|roller|suitcase|travel
⌛	0	沙漏|时间|计时|计时器	hourglass done|done|hourglass|sand|time|timer
⏳	0	沙正往下流的沙漏|沙|沙漏|等待|计时器	hourglass not done|done|flowing|hourglass|hours|not|sand|timer|waiting|yolo
⌚	0	手表|时间|表	watch|clock|time
⏰	0	闹钟|小时|时间|钟	alarm clock|alarm|clock|hours|hrs|late|time|waiting
⏱️	0	秒表|码表|计时|计时器	stopwatch|clock|time
⏲️	0	定时器|时间|计时|计时器	timer clock|clock|timer
🕰️	0	座钟|台钟|壁炉钟|时钟	mantelpiece clock|clock|mantelpiece|time
🕛	0	十二点|00|12|12:00|整点|时间|点钟|钟	twelve o’clock|12|12:00|clock|o’clock|time|twelve
🕧	0	十二点半|12|12:30|30|时钟	twelve-thirty|12|12:30|30|clock|thirty|time|twelve
🕐	0	一点|00|1|1:00|时间	one o’clock|1|1:00|clock|o’clock|one|time
🕜	0	一点半|1|1:30|30|时间|钟	one-thirty|1|1:30|30|clock|one|thirty|time
🕑	0	两点|00|2|2:00|时钟	two o’clock|2|2:00|clock|o’clock|time|two
🕝	0	两点半|2|2:30|30|时间|钟	two-thirty|2|2:30|30|clock|thirty|time|two
🕒	0	三点|00|3|3:00|时钟	three o’clock|3|3:00|clock|o’clock|three|time
🕞	0	三点半|3|3:30|30|时间|钟	three-thirty|3|3:30|30|clock|thirty|three|time
🕓	0	四点|00|4|4:00|时钟	four o’clock|4|4:00|clock|four|o’clock|time
🕟	0	四点半|30|4|4:30|时间|钟	four-thirty|30|4|4:30|clock|four|thirty|time
🕔	0	五点|00|5|5:00|时钟	five o’clock|5|5:00|clock|five|o’clock|time
🕠	0	五点半|30|5|5:30|时钟	five-thirty|30|5|5:30|clock|five|thirty|time
🕕	0	六点|00|6|6:00|时钟	six o’clock|6|6:00|clock|o’clock|six|time
🕡	0	六点半|30|6|6:30|时钟	six-thirty|30|6|6:30|clock|six|thirty
🕖	0	七点|00|7|7:00|时钟	seven o’clock|0|7|7:00|clock|o’clock|seven
🕢	0	七点半|30|7|7:30|时钟	seven-thirty|30|7|7:30|clock|seven|thirty
🕗	0	八点|00|8|8:00|时间|钟	eight o’clock|8|8:00|clock|eight|o’clock|time
🕣	0	八点半|30|8|8:30|时钟	eight-thirty|30|8|8:30|clock|eight|thirty|time
🕘	0	九点|00|9|9:00|时钟	nine o’clock|9|9:00|clock|nine|o’clock|time
🕤	0	九点半|30|9|9:30|时钟	nine-thirty|30|9|9:30|clock|nine|thirty|time
🕙	0	十点|00|10|10:00|时钟	ten o’clock|0|10|10:00|clock|o’clock|ten
🕥	0	十点半|10|10:30|30|时钟	ten-thirty|10|10:30|30|clock|ten|thirty|time
🕚	0	十一点|00|11|11:00|时钟	eleven o’clock|11|11:00|clock|eleven|o’clock|time
🕦	0	十一点半|11|11:30|30|时钟	eleven-thirty|11|11:30|30|clock|eleven|thirty|time
🌑	0	朔月|新月|月亮	new moon|dark|moon|new|space
🌒	0	蛾眉月|三日月|娥眉月|弯月|月亮|盈月|眉月	waxing crescent moon|crescent|dreams|moon|space|waxing
🌓	0	上弦月|月亮	first quarter moon|first|moon|quarter|space
🌔	0	盈凸月|月亮	waxing gibbous moon|gibbous|moon|space|waxing
🌕	0	满月|月亮|望月	full moon|full|moon|space
🌖	0	亏凸月|月亮|衰落	waning gibbous moon|gibbous|moon|space|waning
🌗	0	下弦月|月亮	last quarter moon|last|moon|quarter|space
🌘	0	残月|亏眉月|弯月|月亮	waning crescent moon|crescent|moon|space|waning
🌙	0	弯月|娥眉月|新月形|月亮|残月|蛾眉月	crescent moon|crescent|moon|ramadan|space
🌚	0	微笑的朔月|新月|月亮|朔月	new moon face|face|moon|new|space
🌛	0	微笑的上弦月|上弦月|月亮|蛾眉月	first quarter moon face|face|first|moon|quarter|space
🌜	0	微笑的下弦月|下弦月|月亮|残月	last quarter moon face|dreams|face|last|moon|quarter
🌡️	0	温度计|天气|气温|温度	thermometer|weather
☀️	0	太阳|光线|晴|晴天|阳光明媚|阳光普照	sun|bright|rays|space|sunny|weather
🌝	0	微笑的月亮|月亮|望月|满月	full moon face|bright|face|full|moon
🌞	0	微笑的太阳|太阳|温暖阳光|阳光明媚	sun with face|beach|bright|day|face|heat|shine|sun|sunny|sunshine|weather
🪐	0	有环行星|土星|行星	ringed planet|planet|ringed|saturn|saturnine
⭐	0	星星|五角星|白色星星	star|astronomy|medium|stars|white
🌟	0	闪亮的星星|发光|星星|闪亮|闪光	glowing star|glittery|glow|glowing|night|shining|sparkle|star|win
🌠	0	流星|夜晚|太空|星空|陨落之星	shooting star|falling|night|shooting|space|star
🌌	0	银河|太空|星空	milky way|milky|space|way
☁️	0	云|云彩|云朵|天气|阴	cloud|weather
⛅	0	阴|乌云蔽日|多云	sun behind cloud|behind|cloud|cloudy|sun|weather
⛈️	0	雷阵雨|暴风雨|阵雨|雨|雷|雷暴	cloud with lightning and rain|cloud|lightning|rain|thunder|thunderstorm
🌤️	0	晴偶有云|云|天气|太阳|少云|晴|阴	sun behind small cloud|behind|cloud|sun|weather
🌥️	0	多云|云|太阳|泠|阴	sun behind large cloud|behind|cloud|sun|weather
🌦️	0	晴转雨|下雨|云|天气|太阳|晴时多云偶阵雨|雨	sun behind rain cloud|behind|cloud|rain|sun|weather
🌧️	0	下雨|云|天气|雨	cloud with rain|cloud|rain|weather
🌨️	0	下雪|云|天气|雪	cloud with snow|cloud|cold|snow|weather
🌩️	0	打雷|云|天气|闪电|雷	cloud with lightning|cloud|lightning|weather
🌪️	0	龙卷风|云|天气|旋风	tornado|cloud|weather|whirlwind
🌫️	0	雾|云|霾	fog|cloud|weather
🌬️	0	大风|狂风|风吹	wind face|blow|cloud|face|wind
🌀	0	台风|天气|旋风|晕|气旋|飓风|龙卷风	cyclone|dizzy|hurricane|twister|typhoon|weather
🌈	0	彩虹|LGBT|双性恋|同志|跨性别	rainbow|gay|genderqueer|glbt|glbtq|lesbian|lgbt|lgbtq|lgbtqia|nature|pride|queer|rain|trans|transgender|weather
🌂	0	收起的伞|下雨|伞|雨|雨伞	closed umbrella|closed|clothing|rain|umbrella
☂️	0	伞|雨|雨伞	umbrella|clothing|rain
☔	0	雨伞|下雨|伞|雨滴	umbrella with rain drops|clothing|drop|drops|rain|umbrella|weather
⛱️	0	阳伞|下雨|伞|地上的阳伞|太阳	umbrella on ground|ground|rain|sun|umbrella
⚡	0	高压|危险|有电|闪电	high voltage|danger|electric|electricity|high|lightning|nature|thunder|thunderbolt|voltage|zap
❄️	0	雪花|冷|天气|雪	snowflake|cold|snow|weather
☃️	0	雪与雪人|泠|雪|雪人	snowman|cold|man|snow
⛄	0	雪人|下雪|泠	snowman without snow|cold|man|snow|snowman
☄️	0	彗星|太空	comet|space
🔥	0	火焰|火|烧|燃烧	fire|af|burn|flame|hot|lit|litaf|tool
💧	0	水滴|冷|天气|水|泪|眼泪	droplet|cold|comic|drop|nature|sad|sweat|tear|water|weather
🌊	0	浪花|波浪|浪|海洋	water wave|nature|ocean|surf|surfer|surfing|water|wave
🎃	0	南瓜灯|万圣节|南瓜|庆祝|灯|灯笼	jack-o-lantern|celebration|halloween|jack|lantern|pumpkin
🎄	0	圣诞树|圣诞|庆祝|树|装饰	christmas tree|celebration|christmas|tree
🎆	0	焰火|庆典|庆祝|炮竹|烟花|爆竹	fireworks|boom|celebration|entertainment|yolo
🎇	0	烟花|庆祝|火花|烟火|焰火	sparkler|boom|celebration|fireworks|sparkle
🧨	0	爆竹|光亮|火花|炸药|烟火|烟花|爆炸|鞭炮	firecracker|dynamite|explosive|fire|fireworks|light|pop|popping|spark
✨	0	闪亮|星星|火花|闪光|闪耀	sparkles|*|magic|sparkle|star
🎈	0	气球|庆祝|生日|节日	balloon|birthday|celebrate|celebration
🎉	0	拉炮彩带|兴奋|呱呱叫|庆祝|彩带|拉炮|派对|派对礼宾花|生日	party popper|awesome|birthday|celebrate|celebration|excited|hooray|party|popper|tada|woohoo
🎊	0	五彩纸屑球|五彩纸屑|庆祝|彩色纸屑|球|舞会	confetti ball|ball|celebrate|celebration|confetti|party|woohoo
🎋	0	七夕树|七夕|庆祝|日本|条幅|树	tanabata tree|banner|celebration|japanese|tanabata|tree
🎍	0	门松|庆祝|日本|松树|盆栽|竹	pine decoration|bamboo|celebration|decoration|japanese|pine|plant
🎎	0	日本人形|人偶|娃娃|庆祝|日本|日本人偶|节日	japanese dolls|celebration|doll|dolls|festival|japanese
🎏	0	鲤鱼旗|庆祝|日本|男孩节|长旗	carp streamer|carp|celebration|streamer
🎐	0	风铃|庆祝|铃铛|风	wind chime|bell|celebration|chime|wind
🎑	0	赏月|中秋|佳节|庆祝|月亮|祭月	moon viewing ceremony|celebration|ceremony|moon|viewing
🧧	0	红包|利事|利是|好运|礼物|红信封|运气|钱	red envelope|envelope|gift|good|hóngbāo|lai|luck|money|red|see
🎀	0	蝴蝶结|丝带|庆祝|缎带	ribbon|celebration
🎁	0	礼物|包礼物|包装|圣诞|庆祝|惊喜|生日礼物|盒子|礼品	wrapped gift|birthday|bow|box|celebration|christmas|gift|present|surprise|wrapped
🎗️	0	提示丝带|丝带|庆典|庆祝|暗示|飘带	reminder ribbon|celebration|reminder|ribbon
🎟️	0	入场券|票|门票	admission tickets|admission|ticket|tickets
🎫	0	票|入场券|电影票|票根|车票|门票	ticket|admission|stub
🎖️	0	军功章|军队|勋章|奖章	military medal|award|celebration|medal|military
🏆	0	奖杯|冠军|奖励|奖品|奖赏|胜利|获胜	trophy|champion|champs|prize|slay|sport|victory|win|winning
🏅	0	奖牌|获胜|运动会奖牌|运动员|金牌	sports medal|award|gold|medal|sports|winner
🥇	0	金牌|奖牌|第一|第一名奖牌	1st place medal|1st|first|gold|medal|place
🥈	0	银牌|亚军|奖牌|第二|第二名奖牌	2nd place medal|2nd|medal|place|second|silver
🥉	0	铜牌|奖牌|季军|第三|第三名奖牌	3rd place medal|3rd|bronze|medal|place|third
⚽	0	足球|大罗|梅西|球|球赛|罗纳尔多|胖罗|英式足球|运动	soccer ball|ball|football|futbol|soccer|sport
⚾	0	棒球|球|运动	baseball|ball|sport
🥎	0	垒球|手套|球|腋下|运动	softball|ball|glove|sports|underarm
🏀	0	篮球|打球|球|篮筐|运动	basketball|ball|hoop|sport
🏐	0	排球|球|球赛	volleyball|ball|game
🏈	0	美式橄榄球|橄榄球|球	american football|american|ball|bowl|football|sport|super
🏉	0	英式橄榄球|橄榄球|球|运动	rugby football|ball|football|rugby|sport
🎾	0	网球|球|球拍|网球拍	tennis|ball|racquet|sport
🥏	0	飞盘|圆盘|极限|极限运动|终极	flying disc|disc|flying|ultimate
🎳	0	保龄球|全倒|球|运动	bowling|ball|game|sport|strike
🏏	0	板球|球|球拍	cricket game|ball|bat|cricket|game
🏑	0	曲棍球|球|球棍|球赛	field hockey|ball|field|game|hockey|stick
🏒	0	冰球|冰球杆|球|球棍	ice hockey|game|hockey|ice|puck|stick
🥍	0	袋棍球|得分|球|球棍|球门|运动|长曲棍球	lacrosse|ball|goal|sports|stick
🏓	0	乒乓球|乒乓|桌球|比赛|球|球拍	ping pong|ball|bat|game|paddle|ping|pingpong|pong|table|tennis
🏸	0	羽毛球|球拍|羽球	badminton|birdie|game|racquet|shuttlecock
🥊	0	拳击手套|手套|拳击	boxing glove|boxing|glove
🥋	0	练武服|制服|柔道|武术|空手道|跆拳道	martial arts uniform|arts|judo|karate|martial|taekwondo|uniform
🥅	0	球门|球网	goal net|goal|net
⛳	0	高尔夫球洞|果岭|果岭旗|球洞|高尔夫|高球	flag in hole|flag|golf|hole|sport
⛸️	0	滑冰|冰刀|溜冰	ice skate|ice|skate|skating
🎣	0	钓鱼竿|钓竿|鱼杆	fishing pole|entertainment|fish|fishing|pole|sport
🤿	0	潜水面罩|浮潜|深潜|潜水	diving mask|diving|mask|scuba|snorkeling
🎽	0	运动背心|上衣|跑步|运动服|饰带	running shirt|athletics|running|sash|shirt
🎿	0	滑雪|运动|雪	skis|ski|snow|sport
🛷	0	雪橇|下雪|乘雪橇|平底雪橇|驾雪橇	sled|luge|sledge|sleigh|snow|toboggan
🥌	0	冰壶|冰上溜石|比赛|游戏|石壶	curling stone|curling|game|rock|stone
🎯	0	正中靶心的飞镖|命中|标的|直接命中|要害|靶心|飞镖	bullseye|bull|dart|direct|entertainment|game|hit|target
🪀	0	悠悠球|上下起落|溜溜球|犹豫不决|玩具	yo-yo|fluctuate|toy
🪁	0	风筝|翱翔|飞翔	kite|fly|soar
🔫	0	水枪|工具|左轮|手枪|枪|武器	water pistol|gun|handgun|pistol|revolver|tool|water|weapon
🎱	0	台球|8 球制桌球|8号球|台球台|游戏|霹雳八球	pool 8 ball|8|8ball|ball|billiard|eight|game|pool
🔮	0	水晶球|命运|工具|梦幻|水晶|球|童话|财富|魔法	crystal ball|ball|crystal|fairy|fairytale|fantasy|fortune|future|magic|tale|tool
🪄	0	魔棒|女巫|巫师|魔术|魔术师|魔杖|魔法	magic wand|magic|magician|wand|witch|wizard
🎮	0	游戏手柄|手柄|游戏|游戏控制器|电子游戏	video game|controller|entertainment|game|video
🕹️	0	游戏操控杆|操控杆|游戏|电子游戏	joystick|game|video|videogame
🎰	0	老虎机|吃角子老虎|游戏|角子机|赌博|赌场	slot machine|casino|gamble|gambling|game|machine|slot|slots
🎲	0	骰子|掷骰子|色子|骰子游戏	game die|dice|die|entertainment|game
🧩	0	拼图|图片|智力游戏|相扣|线索|联锁|部件	puzzle piece|clue|interlocking|jigsaw|piece|puzzle
🧸	0	泰迪熊|填充|毛绒玩具|熊|玩偶|玩具|玩物|长毛绒	teddy bear|bear|plaything|plush|stuffed|teddy|toy
🪅	0	彩罐|五月节|庆祝|皮纳塔|糖果|聚会|节日|墨西哥	piñata|candy|celebrate|celebration|cinco|de|festive|mayo|party|pinada|pinata
🪩	0	镜球|派对|聚会|舞会|舞厅|舞蹈|蹦迪|迪斯科|闪耀	mirror ball|ball|dance|disco|glitter|mirror|party
🪆	0	套娃|俄罗斯套娃|俄罗斯娃娃|娃娃	nesting dolls|babooshka|baboushka|babushka|doll|dolls|matryoshka|nesting|russia
♠️	0	黑桃|扑克|牌|葵扇|黑桃花色	spade suit|card|game|spade|suit
♥️	0	红桃|扑克|牌|红心|红桃花色	heart suit|card|emotion|game|heart|hearts|suit
♦️	0	方片|扑克|方块|牌|牌局	diamond suit|card|diamond|game|suit
♣️	0	梅花|扑克|梅花花色|牌|草花	club suit|card|club|clubs|game|suit
♟️	0	兵|受骗者|国际象棋|牺牲品	chess pawn|chess|dupe|expendable|pawn
🃏	0	大小王|大王|小丑|小王|扑克|扑克小丑|牌|百搭牌|鬼牌	joker|card|game|wildcard
🀄	0	红中|方城之战|牌局|麻将|麻将红中	mahjong red dragon|dragon|game|mahjong|red
🎴	0	花札|卡牌|日本|游戏|花斗|花牌	flower playing cards|card|cards|flower|game|japanese|playing
🎭	0	表演艺术|剧院|女演员|戏剧|演员|艺术|莎士比亚|表演|面具	performing arts|actor|actress|art|arts|entertainment|mask|performing|theater|theatre|thespian
🖼️	0	带框的画|加框的照片|博物馆|框|照片|画|画框|艺术	framed picture|art|frame|framed|museum|painting|picture
🎨	0	调色盘|创意|博物馆|多种色彩|娱乐|画家|画画|绘画|艺术|调色板	artist palette|art|artist|artsy|arty|colorful|creative|entertainment|museum|painter|painting|palette
🧵	0	线|卷盘|线轴|绳子|缝纫|针|针线	thread|needle|sewing|spool|string
🪡	0	缝合针|线|绣花针|缝合|缝纫|缝线|缝衣针|裁剪|针	sewing needle|embroidery|needle|sew|sewing|stitches|sutures|tailoring|thread
🧶	0	毛线|毛线球|线球|编织|钩针编织	yarn|ball|crochet|knit
🪢	0	结|八字结|打结|绳子|绳扣|绳结|缠结|麻线	knot|cord|rope|tangled|tie|twine|twist
👓	0	眼镜|服饰|眼睛	glasses|clothing|eye|eyeglasses|eyewear
🕶️	0	墨镜|太阳镜	sunglasses|dark|eye|eyewear|glasses
🥽	0	护目镜|护目|护眼|水肺|游泳|潜水|焊接	goggles|dive|eye|protection|scuba|swimming|welding
🥼	0	白大褂|医生|外衣|实验|实验人员|实验室白大褂|实验服|白衣|科学家|衣服	lab coat|clothes|coat|doctor|dr|experiment|jacket|lab|scientist|white
🦺	0	救生衣|安全|紧急|背心|逃生	safety vest|emergency|safety|vest
👔	0	领带|工作|正式|衬衫领带	necktie|clothing|employed|serious|shirt|tie
👕	0	T恤|休闲服装|恤衫	t-shirt|blue|casual|clothes|clothing|collar|dressed|shirt|shopping|tshirt|weekend
👖	0	牛仔裤|休闲|周末|蓝色|裤子	jeans|blue|casual|clothes|clothing|denim|dressed|pants|shopping|trousers|weekend
🧣	0	围巾|冷|包紧|围脖|头巾	scarf|bundle|cold|neck|up
🧤	0	手套|手	gloves|hand
🧥	0	外套|冷|夹克|超冷	coat|brr|bundle|cold|jacket|up
🧦	0	袜子|短袜|袜|长袜	socks|stocking
👗	0	连衣裙|衣服|裙子	dress|clothes|clothing|dressed|fancy|shopping
👘	0	和服|日本|衣服	kimono|clothing|comfortable
🥻	0	纱丽|印度|披肩|莎丽|衣服|连衣裙	sari|clothing|dress
🩱	0	连体泳衣|一片式|泳衣|泳装|游泳|连身泳衣	one-piece swimsuit|bathing|one-piece|suit|swimsuit
🩲	0	三角裤|一片式|内裤|泳衣|泳装|短裤	briefs|bathing|one-piece|suit|swimsuit|underwear
🩳	0	短裤|内裤|四角裤|泳衣|泳装|泳裤|裤子	shorts|bathing|pants|suit|swimsuit|underwear
👙	0	比基尼|三点式|泳装|游泳	bikini|bathing|beach|clothing|pool|suit|swim
👚	0	女装|女|女生衣服|女衬衫|衣服	woman’s clothes|blouse|clothes|clothing|collar|dress|dressed|lady|shirt|shopping|woman|woman’s
🪭	0	折扇|凉|凉快|啪嗒声|害羞|扇|扇动|扇子|拍手|热|羞涩|腼腆|舞蹈|调情|跳舞|降温	folding hand fan|clack|clap|cool|cooling|dance|fan|flirt|flutter|folding|hand|hot|shy
👛	0	钱包|血拼|铜板	purse|clothes|clothing|coin|dress|fancy|handbag|shopping
👜	0	手提包|包包|挎包|血拼	handbag|bag|clothes|clothing|dress|lady|purse|shopping
👝	0	手袋|包|化妆包|手拿|手拿包	clutch bag|bag|clothes|clothing|clutch|dress|handbag|pouch|purse
🛍️	0	购物袋|包|袋|购物|逛街	shopping bags|bag|bags|hotel|shopping
🎒	0	书包|上学|包	backpack|backpacking|bag|bookbag|education|rucksack|satchel|school
🩴	0	夹趾凉鞋|人字拖|凉鞋|沙滩|沙滩凉鞋|草屡|鞋	thong sandal|beach|flip|flop|sandal|sandals|shoe|thong|thongs|zōri
👞	0	男鞋|棕色|皮鞋|鞋	man’s shoe|brown|clothes|clothing|feet|foot|kick|man|man’s|shoe|shoes|shopping
👟	0	跑鞋|跑|运动鞋|鞋	running shoe|athletic|clothes|clothing|fast|kick|running|shoe|shoes|shopping|sneaker|tennis
🥾	0	登山鞋|健行|徒步|户外|登山|背包|远足野营|露营|靴子|鞋	hiking boot|backpacking|boot|brown|camping|hiking|outdoors|shoe
🥿	0	平底鞋|一脚蹬|便鞋|平底芭蕾舞鞋|芭蕾舞鞋	flat shoe|ballet|comfy|flat|flats|shoe|slip-on|slipper
👠	0	高跟鞋|女|时装|鞋|高跟	high-heeled shoe|clothes|clothing|dress|fashion|heel|heels|high-heeled|shoe|shoes|shopping|stiletto|woman
👡	0	女式凉鞋|凉鞋|女	woman’s sandal|clothing|sandal|shoe|woman|woman’s
🩰	0	芭蕾舞鞋|舞蹈|舞鞋|足尖鞋|跳舞	ballet shoes|ballet|dance|shoes
👢	0	女靴|女|女式靴子|靴子	woman’s boot|boot|clothes|clothing|dress|shoe|shoes|shopping|woman|woman’s
🪮	0	发夹|圆蓬|头发|夹子|小刷子|梳子|梳理|爆炸头|非洲头	hair pick|afro|comb|groom|hair|pick
👑	0	皇冠|国王|权力的游戏|王冠|王后|皇家	crown|clothing|family|king|medieval|queen|royal|royalty|win
👒	0	女帽|女|女式|帽子|花园派对	woman’s hat|clothes|clothing|garden|hat|hats|party|woman|woman’s
🎩	0	礼帽|帽子|正式|高帽	top hat|clothes|clothing|fancy|formal|hat|magic|top|tophat
🎓	0	毕业帽|四方帽|学位|学者|毕业	graduation cap|cap|celebration|clothing|education|graduation|hat|scholar
🧢	0	鸭舌帽|帽子|棒球帽	billed cap|baseball|bent|billed|cap|dad|hat
🪖	0	军用头盔|军事|军用|军队|士兵|头盔|战争|战士|部队	military helmet|army|helmet|military|soldier|war|warrior
⛑️	0	白十字头盔|十字|头盔|安全帽|救援人员头盔|脸	rescue worker’s helmet|aid|cross|face|hat|helmet|rescue|worker’s
📿	0	念珠|宗教|珠子|祈祷|项链	prayer beads|beads|clothing|necklace|prayer|religion
💄	0	唇膏|化妆|化妆品|口红|约会	lipstick|cosmetics|date|makeup
💍	0	戒指|结婚|订婚|钻戒|闪	ring|diamond|engaged|engagement|married|romance|shiny|sparkling|wedding
💎	0	宝石|婚礼|珠宝|订婚|钻石	gem stone|diamond|engagement|gem|jewel|money|romance|stone|wedding
🔇	0	已静音的扬声器|声音|安静|扬声器|扬声器关闭|无声|静音	muted speaker|mute|muted|quiet|silent|sound|speaker
🔈	0	低音量的扬声器|低音量扬扬声|喇叭|小声|小音量|扬声器|轻声|音量	speaker low volume|low|soft|sound|speaker|volume
🔉	0	中等音量的扬声器|中等|中等音量|中音量|中音量扬声器|扬声器	speaker medium volume|medium|sound|speaker|volume
🔊	0	高音量的扬声器|大声|大音量|扬声器|音量|高音量	speaker high volume|high|loud|music|sound|speaker|volume
📢	0	喇叭|公共广播|大声|广播|扩音器|通知	loudspeaker|address|communication|loud|public|sound
📣	0	扩音器|呼喊|喇叭|喇叭筒|大声|通知	megaphone|cheering|sound
📯	0	邮号|号|号角|喇叭|邮政	postal horn|horn|post|postal
🔔	0	铃铛|叮当|响铃|钟|钟声|铃声	bell|break|church|sound
🔕	0	禁止响铃|响铃关闭|安静|无声|铃|静音	bell with slash|bell|forbidden|mute|no|not|prohibited|quiet|silent|slash|sound
🎼	0	乐谱|五线谱|曲谱|音乐|音符	musical score|music|musical|note|score
🎵	0	音符|乐谱|五线谱|八分音符|音乐	musical note|music|musical|note|sound
🎶	0	多个音符|乐谱|五线谱|八分音符|音乐|音符	musical notes|music|musical|note|notes|sound
🎙️	0	录音室麦克风|录音室|音乐|麦|麦克|麦克风	studio microphone|mic|microphone|music|studio
🎚️	0	电平滑块|滑块|电平|调节|调节滑块|音乐|音量	level slider|level|music|slider
🎛️	0	控制旋钮|控制|旋钮|调节|音乐	control knobs|control|knobs|music
🎤	0	麦克风|k歌|卡拉ok|卡拉OK|唱K|唱歌|麦|麦克	microphone|karaoke|mic|music|sing|sound
🎧	0	耳机|头戴式耳机|耳塞	headphone|earbud|sound
📻	0	收音机|娱乐|广播|广播电台|无线电|电台	radio|entertainment|tbt|video
🎷	0	萨克斯管|乐器|吹奏|演奏|萨克斯风|音乐	saxophone|instrument|music|sax
🪗	0	手风琴|乐器|六角形风琴|音乐|风琴	accordion|box|concertina|instrument|music|squeeze|squeezebox
🎸	0	吉他|乐器|弹奏|演奏|电吉他|音乐	guitar|instrument|music|strat
🎹	0	音乐键盘|乐器|弹奏|演奏|钢琴|音乐	musical keyboard|instrument|keyboard|music|musical|piano
🎺	0	小号|乐器|吹奏|喇叭|音乐	trumpet|instrument|music
🎻	0	小提琴|乐器|提琴|是特拉迪瓦尔|演奏|音乐	violin|instrument|music
🪕	0	班卓琴|弦乐器|弹奏|音乐	banjo|music|stringed
🥁	0	鼓|音乐|鼓声|鼓槌	drum|drumsticks|music
🪘	0	长鼓|乐器|康加鼓|康茄鼓|敲|节奏|非洲手鼓|鼓	long drum|beat|conga|drum|instrument|long|rhythm
🪇	0	沙球|乐器|恰恰|打击乐器|拨浪鼓|摇|摇动|沙槌|沙铃|派对|舞蹈|音乐	maracas|cha|dance|instrument|music|party|percussion|rattle|shake|shaker
🪈	0	长笛|乐器|乐队|木管乐器|横笛|短笛|竖笛|管乐器|菲菲笛|长笛手|音乐	flute|band|fife|flautist|instrument|marching|music|orchestra|piccolo|pipe|recorder|woodwind
📱	0	手机|手提电话|智能手机|电话|移动|移动电话|移动通信|通信	mobile phone|cell|communication|mobile|phone|telephone
📲	0	带有箭头的手机|手机|接收|智能手机|来电|电话|移动电话|箭头|通信	mobile phone with arrow|arrow|build|call|cell|communication|mobile|phone|receive|telephone
☎️	0	电话|固定电话|固话|座机	telephone|phone
📞	0	电话听筒|听筒|固定电话|固话|座机|电话|通信	telephone receiver|communication|phone|receiver|telephone|voip
📟	0	寻呼机|BB 机|传呼机|呼机|通信	pager|communication
📠	0	传真机|传真|传真号|发传真	fax machine|communication|fax|machine
🔋	0	电池|正极|电|电极|电源|蓄电池|负极	battery
🪫	0	电池电量不足|低能量|电子|电池|电池电量低|电量不足	low battery|battery|drained|electronic|energy|low|power
🔌	0	电源插头|插头|电插头|电源|电线	electric plug|electric|electricity|plug
💻	0	笔记本电脑|PC|个人电脑|手提电脑|电脑	laptop|computer|office|pc|personal
🖥️	0	台式电脑|PC|个人电脑|台式|显示器|显示屏|电脑|计算机	desktop computer|computer|desktop|monitor
🖨️	0	打印机|印刷机|喷墨打印|复印|打印|扫描|激光打印	printer|computer
⌨️	0	键盘|打字|按键|电脑|输入	keyboard|computer
🖱️	0	电脑鼠标|有线鼠标|激光鼠标|点击|点按|电脑|鼠标	computer mouse|computer|mouse
🖲️	0	轨迹球|有线鼠标|电脑|追踪球|鼠标	trackball|computer
💽	0	电脑光盘|MD|minidisk|mini光盘|光盘|电脑|迷你光盘|迷你光碟|迷你唱片	computer disk|computer|disk|minidisk|optical
💾	0	软盘|3.5英寸|便携|存储|电脑|磁盘	floppy disk|computer|disk|floppy
💿	0	光盘|cd|专辑|存储|影片|蓝光|音乐	optical disk|blu-ray|cd|computer|disk|dvd|optical
📀	0	DVD|dvd|光盘|光碟|影片|电脑|蓝光|音乐	dvd|blu-ray|cd|computer|disk|dvd|optical
🧮	0	算盘|计算|计算器	abacus|calculation|calculator
🎥	0	电影摄影机|录像|摄像机|摄录机|摄影|摄影机|电影	movie camera|bollywood|camera|cinema|film|hollywood|movie|record
🎞️	0	影片帧|帧|电影|电影胶卷|电影胶片|胶卷|胶片	film frames|cinema|film|frames|movie
📽️	0	电影放映机|影片|投影仪|放映机|电影|视频	film projector|cinema|film|movie|projector|video
🎬	0	场记板|场记|打板|拍电影	clapper board|action|board|clapper|movie
📺	0	电视机|电视|看电视|视频|节目	television|tv|video
📷	0	相机|卡片相机|拍照|摄影|照片|照相机|自拍	camera|photo|selfie|snap|tbt|trip|video
📸	0	开闪光灯的相机|带闪光灯的相机|拍照|相机|闪光灯|闪光灯打开	camera with flash|camera|flash|video
📹	0	摄像机|录像|录像机|录影|拍摄|摄影机|视频	video camera|camcorder|camera|tbt|video
📼	0	录像带|VHS|录影带|磁带	videocassette|old|school|tape|vcr|vhs|video
🔍	0	左斜的放大镜|工具|搜索|放大|放大镜|查找	magnifying glass tilted left|glass|lab|left|left-pointing|magnifying|science|search|tilted|tool
🔎	0	右斜的放大镜|工具|搜索|放大|放大镜|查找	magnifying glass tilted right|contact|glass|lab|magnifying|right|right-pointing|science|search|tilted|tool
🕯️	0	蜡烛|光|烛光|烛火|照明|燃烧	candle|light
💡	0	灯泡|主意|想法|点子|电|电灯泡|白炽灯	light bulb|bulb|comic|electric|idea|light
🔦	0	手电筒|光|工具|手电|照明|电筒	flashlight|electric|light|tool|torch
🏮	0	红灯笼|光|喜庆|居酒屋|日本|灯笼|节日|酒馆|餐馆	red paper lantern|bar|lantern|light|paper|red|restaurant
🪔	0	印度油灯|排灯节|油|灯|迪亚	diya lamp|diya|lamp|light|oil
📔	0	精装笔记本|书|写作|学校|封面|教育|笔记本	notebook with decorative cover|book|cover|decorated|decorative|education|notebook|school|writing
📕	0	合上的书本|书|书本|书本合起|合上	closed book|book|closed|education
📖	0	打开的书本|书|书本|图书馆|小说|开卷|打开|知识|读书|阅读	open book|book|education|fantasy|knowledge|library|novels|open|reading
📗	0	绿色书本|书|书本|图书馆|教育|绿|绿皮书|绿色|阅读	green book|book|education|fantasy|green|library|reading
📘	0	蓝色书本|书|书本|图书馆|教育|篮|蓝皮书|蓝色|阅读	blue book|blue|book|education|fantasy|library|reading
📙	0	橙色书本|书|书本|图书馆|教育|橘皮书|橘色|橙色|阅读	orange book|book|education|fantasy|library|orange|reading
📚	0	书|书本|书籍|图书|图书馆|学习|学校|小说|教育|知识|阅读	books|book|education|fantasy|knowledge|library|novels|reading|school|study
📓	0	笔记本|日记本|本子|笔记|记事本|记录	notebook
📒	0	账本|笔记本|记事本|记账|账簿	ledger|notebook
📃	0	带卷边的页面|卷曲|卷边|文书|文件|文档|纸张|页面	page with curl|curl|document|page|paper
📜	0	卷轴|卷纸|画卷|纸|纸卷|羊皮纸	scroll|paper
📄	0	文件|文书|文档|页面向上	page facing up|document|facing|page|paper|up
📰	0	报纸|传播|报道|新闻|看报|纸|读报	newspaper|communication|news|paper
🗞️	0	报纸卷|卷起|卷起的报纸|报纸|新闻|纸	rolled-up newspaper|news|newspaper|paper|rolled|rolled-up
📑	0	标签页|书签|书签页标签|有书签的页面|标签	bookmark tabs|bookmark|mark|marker|tabs
🔖	0	书签|标签|读书|阅读	bookmark|mark
🏷️	0	标签|吊牌|标记|行李牌	label|tag
💰	0	钱袋|付钱|十亿|变现|守财奴|富有|有钱|现金|百万|美元|赌钱|赢钱|钱|钱包|银行	money bag|bag|bank|bet|billion|cash|cost|dollar|gold|million|money|moneybag|paid|paying|pot|rich|win
🪙	0	硬币|富有|欧元|美元|财富|金|金属|金币|钱|银	coin|dollar|euro|gold|metal|money|rich|silver|treasure
💴	0	日元|日币|现金|纸币|货币|钞票|钱|银行	yen banknote|bank|banknote|bill|currency|money|note|yen
💵	0	美元|现金|纸币|美刀|美钞|货币|钱|银行	dollar banknote|bank|banknote|bill|currency|dollar|money|note
💶	0	欧元|现金|纸币|货币|钞票|钱|银行	euro banknote|100|bank|banknote|bill|currency|euro|money|note|rich
💷	0	英镑|现金|纸币|货币|钞票|钱|银行	pound banknote|bank|banknote|bill|billion|cash|currency|money|note|pound|pounds
💸	0	长翅膀的钱|纸币|翅膀|花钱|钱|飞	money with wings|bank|banknote|bill|billion|cash|dollar|fly|million|money|note|pay|wings
💳	0	信用卡|信用|借记卡|刷卡|卡|收钱|现金|现金卡|贷记卡|银行|银行卡	credit card|bank|card|cash|charge|credit|money|pay
🧾	0	收据|会计|信封|凭据|发票|收条|簿记|记账|证据|证明|账单	receipt|accounting|bookkeeping|evidence|invoice|proof
💹	0	趋势向上且带有日元符号的图表|上扬|上涨|日元|日元升值|日元汇率|日币|货币|货币升值图表|走势	chart increasing with yen|bank|chart|currency|graph|growth|increasing|market|money|rise|trend|upward|yen
✉️	0	信封|信件|信息|来信|电子邮件|电邮|邮件	envelope|e-mail|email|letter
📧	0	电子邮件|信件|信封|电邮|邮件	e-mail|email|letter|mail
📨	0	来信|信件|信封|发送|接收|收信|收到来信|收到邮件|电子邮件|电邮|邮件	incoming envelope|delivering|e-mail|email|envelope|incoming|letter|mail|receive|sent
📩	0	收邮件|信件|信封|发信|发出|发送|发邮件|有箭头的信封|邮件	envelope with arrow|arrow|communication|down|e-mail|email|envelope|letter|mail|outgoing|send|sent
📤	0	发件箱|信件|发信|发送|发邮件|收件箱|电子邮件|电邮|邮件	outbox tray|box|email|letter|mail|outbox|sent|tray
📥	0	收件箱|信件|接收|收信|收到邮件|电子邮件|电邮|邮件	inbox tray|box|email|inbox|letter|mail|receive|tray|zero
📦	0	包裹|快递|指向|盒子|箱子|装货|运送	package|box|communication|delivery|parcel|shipping
📫	0	有待收信件|信箱|旗标|有新信件|邮箱|邮箱关闭红旗升起	closed mailbox with raised flag|closed|communication|flag|mail|mailbox|postbox|raised
📪	0	无待收信件|信箱|信箱关闭红旗放下|放下|旗标|无新信件	closed mailbox with lowered flag|closed|flag|lowered|mail|mailbox|postbox
📬	0	有新信件|信箱|信箱打开红旗升起|打开|旗标|有待收信件	open mailbox with raised flag|flag|mail|mailbox|open|postbox|raised
📭	0	无新信件|信箱|信箱打开|信箱打开红旗放下|旗标|无待收信件|邮件|邮递	open mailbox with lowered flag|flag|lowered|mail|mailbox|open|postbox
📮	0	邮筒|信|信箱|寄信|邮箱	postbox|mail|mailbox
🗳️	0	投票箱|投票|盒子|票箱|选举|选票	ballot box with ballot|ballot|box
✏️	0	铅笔|橡皮|橡皮擦|画画|画笔|笔|绘画	pencil
✒️	0	钢笔尖|写字|硬笔|笔|笔尖|钢笔|黑色笔尖	black nib|black|nib|pen
🖋️	0	钢笔|写字|硬笔|笔	fountain pen|fountain|pen
🖊️	0	笔|原子笔|圆珠笔|油笔	pen|ballpoint
🖌️	0	画笔|刷|毛笔|画刷|笔刷	paintbrush|painting
🖍️	0	蜡笔|油画棒|画棒	crayon
📝	0	备忘录|便条|便条簿|便笺|铅笔	memo|communication|media|notes|pencil
💼	0	公文包|上班|公事包|办公室|包|手提包|文件	briefcase|office
📁	0	文件夹|办公|文件|文具|硬纸夹	file folder|file|folder
📂	0	打开的文件夹|办公|打开|打开文件夹|文件|文件夹|文具	open file folder|file|folder|open
🗂️	0	索引分隔文件夹|分隔|分隔卡|文件夹|索引|隔板	card index dividers|card|dividers|index
📅	0	日历|日期	calendar|date
📆	0	手撕日历|日历|日期	tear-off calendar|calendar|tear-off
🗒️	0	线圈本|文具|笔记本|线圈|记事本	spiral notepad|note|notepad|pad|spiral
🗓️	0	线圈日历|日历|日期|线圈|记事本	spiral calendar|calendar|pad|spiral
📇	0	卡片索引|卡片|卡牌索引|名片索引|目录|索引	card index|card|index|old|rolodex|school
📈	0	趋势向上的图表|上升|上涨|上涨图表|上涨趋势线|向上|图表|成长|趋势线	chart increasing|chart|data|graph|growth|increasing|right|trend|up|upward
📉	0	趋势向下的图表|下跌|下跌图表|下跌趋势线|下降|向下|图表|趋势线	chart decreasing|chart|data|decreasing|down|downward|graph|negative|trend
📊	0	条形图|图形|图表|柱形图|直方图|资料|长条图	bar chart|bar|chart|data|graph
📋	0	剪贴板|写字夹板|写字板|剪贴簿|夹子|待办事项|待办表|纸张	clipboard|do|list|notes
📌	0	图钉|固定|拼贴|按钉	pushpin|collage|pin
📍	0	圆图钉|位置|固定|图钉	round pushpin|location|map|pin|pushpin|round
📎	0	回形针|万字夹|回纹针|曲别针|纸夹	paperclip
🖇️	0	连起来的两个回形针|万字夹|回形针|回纹针|曲别针|纸夹|连接|连接的回形针	linked paperclips|link|linked|paperclip|paperclips
📏	0	直尺|尺|尺子|数学|文具|测量|量|长度	straight ruler|angle|edge|math|ruler|straight|straightedge
📐	0	三角尺|三角|尺|数学|文具|测量|角|角度	triangular ruler|angle|math|rule|ruler|set|slide|triangle|triangular
✂️	0	剪刀|修剪|剪|剪子|剪裁|工具	scissors|cut|cutting|paper|tool
🗃️	0	卡片盒|卡片|存档|文件|标签|档案|箱|索引	card file box|box|card|file
🗄️	0	文件柜|存档|归档|收纳|柜|档案	file cabinet|cabinet|file|filing|paper
🗑️	0	垃圾桶|垃圾|垃圾篓|废纸篓	wastebasket|can|garbage|trash|waste
🔒	0	合上的锁|上锁|私密|锁|锁住|锁头|锁定	locked|closed|lock|private
🔓	0	打开的锁|取消锁定|开锁|打开|破解|解锁|锁	unlocked|cracked|lock|open|unlock
🔏	0	墨水笔和锁|笔|笔尖|钢笔|锁|隐私	locked with pen|ink|lock|locked|nib|pen|privacy
🔐	0	钥匙和锁|安全|脚踏车锁|钥匙|锁|锁上	locked with key|bike|closed|key|lock|locked|secure
🔑	0	钥匙|密码|密钥|开锁|解锁|锁	key|keys|lock|major|password|unlock
🗝️	0	老式钥匙|古老的钥匙|旧钥匙|线索|钥匙	old key|clue|key|lock|old
🔨	0	锤子|修理|家居修缮|工具|敲|施工|砸|铁锤	hammer|home|improvement|repairs|tool
🪓	0	斧头|切|劈|木头|砍	axe|ax|chop|hatchet|split|wood
⛏️	0	铁镐|工具|挖|挖掘|采矿|锄头|鹤嘴锄	pick|hammer|mining|tool
⚒️	0	锤子与镐|工具|铁锤|铁镐|锤子|镐|镐子	hammer and pick|hammer|pick|tool
🛠️	0	锤子与扳手|工具|扳手|铁锤|锤子	hammer and wrench|hammer|spanner|tool|wrench
🗡️	0	匕首|剑|武器|短刀|短剑	dagger|knife|weapon
⚔️	0	交叉放置的剑|交叉|剑|十字|双剑|战死|武器	crossed swords|crossed|swords|weapon
💣	0	炸弹|爆炸	bomb|boom|comic|dangerous|explosion|hot
🪃	0	回旋镖|反弹|回弹|土著|武器|飞镖	boomerang|rebound|repercussion|weapon
🏹	0	弓和箭|人马座|射手|射手座|射箭|弓|弓箭|箭	bow and arrow|archer|archery|arrow|bow|sagittarius|tool|weapon|zodiac
🛡️	0	盾牌|武器|盾|防御	shield|weapon
🪚	0	木工锯|修剪|工具|木匠|木材|锯|锯子	carpentry saw|carpenter|carpentry|cut|lumber|saw|tool|trim
🔧	0	扳手|家居修缮|工具|螺丝扳手	wrench|home|improvement|spanner|tool
🪛	0	螺丝刀|工具|螺丝	screwdriver|flathead|handy|screw|tool
🔩	0	螺母与螺栓|工具|螺丝|螺帽|螺栓|螺母|螺钉	nut and bolt|bolt|home|improvement|nut|tool
⚙️	0	齿轮|传动|工具|机械|零件	gear|cog|cogwheel|tool
🗜️	0	夹钳|压缩|夹具|工具|机械|紧固	clamp|compress|tool|vice
⚖️	0	天平|公平|公正|天秤|天秤座|星座|正义|法律	balance scale|balance|justice|libra|scale|scales|tool|weight|zodiac
🦯	0	盲杖|拐杖|无障碍|盲|盲人	white cane|accessibility|blind|cane|probing|white
🔗	0	链接|网址|链条|锁链	link|links
⛓️	0	链条|铁链|链|锁链	chains|chain
🪝	0	挂钩|卖点|弯钩|抓|曲线|钩子|钩状物|鱼钩	hook|catch|crook|curve|ensnare|point|selling
🧰	0	工具箱|大箱子|工具|机修|箱子|红盒子	toolbox|box|chest|mechanic|red|tool
🧲	0	磁铁|U 型|吸引|吸引力|正负|磁性|马蹄铁	magnet|attraction|horseshoe|magnetic|negative|positive|shape|u
🪜	0	梯子|台阶|梯级|横档|爬|爬梯|阶梯	ladder|climb|rung|step
⚗️	0	蒸馏器|净化|化学|实验|工具|蒸馏	alembic|chemistry|tool
🧪	0	试管|化学|化学家|实验|实验室|科学	test tube|chemist|chemistry|experiment|lab|science|test|tube
🧫	0	培养皿|培养|实验室|生物学|生物学家|细菌	petri dish|bacteria|biologist|biology|culture|dish|lab|petri
🧬	0	DNA|基因|演化|生命|生物学家|进化|遗传学	dna|biologist|evolution|gene|genetics|life
🔬	0	显微镜|实验|实验室|工具|生物|科学|细胞	microscope|experiment|lab|science|tool
🔭	0	望远镜|外星人|天体|天文|天文学|工具|接触|科学|观星	telescope|contact|extraterrestrial|science|tool
📡	0	卫星天线|信号接收|卫星|卫星接收天线|卫星碟形天线|外星人|天线|接触	satellite antenna|aliens|antenna|contact|dish|satellite|science
💉	0	注射器|医学|医生|工具|打针|接种|治疗|疫苗|药|针头|针筒	syringe|doctor|flu|medicine|needle|shot|sick|tool|vaccination
🩸	0	血滴|医疗|月经|流血|献血|经血|输血	drop of blood|bleed|blood|donation|drop|injury|medicine|menstruation
💊	0	药丸|医生|吃药|治疗|生病|用药|维他命|药|药物	pill|doctor|drugs|medicated|medicine|pills|sick|vitamin
🩹	0	创可贴|OK绷|伤口|受伤|绷带|胶布	adhesive bandage|adhesive|bandage
🩼	0	拐杖|受伤|手杖|残疾|活动助行类辅具|辅助	crutch|aid|cane|disability|help|hurt|injured|mobility|stick
🩺	0	听诊器|医生|医疗|心脏|心跳|诊断	stethoscope|doctor|heart|medicine
🩻	0	X射线|X 射线|医生|医疗|骨架|骨骼	x-ray|bones|doctor|medical|skeleton|skull|xray
🚪	0	门|出入口|前门|后门|大门|屋门|房门|房间	door|back|closet|front
🛗	0	电梯|升降机|可达性	elevator|accessibility|hoist|lift
🪞	0	镜子|化妆|反射|反射镜|窥镜	mirror|makeup|reflection|reflector|speculum
🪟	0	窗户|开窗|新鲜空气|景色|窗口|窗框|透明	window|air|frame|fresh|opening|transparent|view
🛏️	0	床|宾馆|床垫|床铺|睡|睡眠|睡觉	bed|hotel|sleep
🛋️	0	沙发和灯|家|沙发|灯|阅读	couch and lamp|couch|hotel|lamp
🪑	0	椅子|坐|坐下|座位|椅背	chair|seat|sit
🚽	0	马桶|WC|卫生间|厕所|洗手间	toilet|bathroom
🪠	0	活塞|便便|吸力|搋子|水管工|通厕所|马桶	plunger|cup|force|plumber|poop|suction|toilet
🚿	0	淋浴|喷头|喷水|水|洗澡 花洒|花洒	shower|water
🛁	0	浴缸|沐浴|泡沫浴|泡澡|洗澡|浴盆|澡盆	bathtub|bath
🪤	0	捕鼠器|奶酪|老鼠夹|诱饵|陷进|陷阱	mouse trap|bait|cheese|lure|mouse|mousetrap|snare|trap
🪒	0	剃须刀|刀|刮|刮刀|剃刀|毛|胡子|锋利	razor|sharp|shave
🧴	0	乳液瓶|乳液|保湿乳液|护肤霜|洗剂瓶|洗发水|洗发露|防嗮霜|防晒霜	lotion bottle|bottle|lotion|moisturizer|shampoo|sunscreen
🧷	0	安全别针|别针|扣针	safety pin|diaper|pin|punk|rock|safety
🧹	0	扫帚|女巫|巫婆|打扫|扫地|清洁	broom|cleaning|sweeping|witch
🧺	0	筐|农作|洗衣|种植|篮子|脏衣篮|野餐	basket|farming|laundry|picnic
🧻	0	卷纸|卫生纸|手纸|纸卷|纸巾	roll of paper|paper|roll|toilet|towels
🪣	0	桶|大桶|木桶|水桶|缸	bucket|cask|pail|vat
🧼	0	皂|杀菌|泡沫|洗手|洗澡|清洁|肥皂|肥皂泡|肥皂盒|肥皂盘	soap|bar|bathing|clean|cleaning|lather|soapdish
🫧	0	气泡|打嗝|水下|泡泡|清洁|漂浮|珍珠状|肥皂|肥皂泡	bubbles|bubble|burp|clean|floating|pearl|soap|underwater
🪥	0	牙刷|刷|刷子|卫生|情节|洗漱|浴室|清洁|牙科|牙齿	toothbrush|bathroom|brush|clean|dental|hygiene|teeth|toiletry
🧽	0	海绵|吸收|吸水|多孔|浸泡|清洁|渗透	sponge|absorbing|cleaning|porous|soak
🧯	0	灭火器|压制|火灾|灭火|熄灭	fire extinguisher|extinguish|extinguisher|fire|quench
🛒	0	购物车|手推车|购物|采购	shopping cart|cart|shopping|trolley
🚬	0	香烟|卷烟|吸烟|抽烟|烟|烟草	cigarette|smoking
⚰️	0	棺材|埋葬|死亡|灵柩|葬礼|陵墓	coffin|dead|death|vampire
🪦	0	墓碑|公墓|坟墓|墓园|墓地|安息|死亡|纪念	headstone|cemetery|dead|grave|graveyard|memorial|rip|tomb|tombstone
⚱️	0	骨灰缸|丧礼|死亡|瓮|缸|葬礼|骨灰|骨灰罐	funeral urn|ashes|death|funeral|urn
🧿	0	纳扎尔护身符|小装饰品|恶魔之眼|护身符|珠子|符咒|纳扎尔|蓝色|邪眼	nazar amulet|amulet|bead|blue|charm|evil-eye|nazar|talisman
🪬	0	法蒂玛之手|保护|好运|手|手掌|护身符|法蒂玛|玛丽|米里亚姆	hamsa|amulet|fatima|fortune|guide|hand|mary|miriam|palm|protect|protection
🗿	0	摩埃|复活岛|复活节岛|复活节岛石像|摩艾|摩艾石像|旅行|毛埃|脸	moai|face|moyai|statue|stoneface|travel
🪧	0	标语牌|告示|布告|标志|标牌|标语|海报|示威|纠察队标语牌|警戒哨	placard|card|demonstration|notice|picket|plaque|protest|sign
🪪	0	身份证|ID|凭证|安全|执照|证件	identification card|card|credentials|document|id|identification|license|security
🏧	0	取款机|ATM|提款机|柜员机|标识|银行	atm sign|atm|automated|bank|cash|money|sign|teller
🚮	0	倒垃圾|垃圾丢弃处|垃圾入篓|垃圾桶	litter in bin sign|bin|litter|litterbin|sign
🚰	0	饮用水|可以喝的|喝水|接水|水|水龙头	potable water|drinking|potable|water
♿	0	轮椅标识|无障碍|残疾|残障|轮椅|轮椅符号	wheelchair symbol|access|handicap|symbol|wheelchair
🚹	0	男厕|卫生间|厕所|洗手间|男士	men’s room|bathroom|lavatory|man|men’s|restroom|room|toilet|wc
🚺	0	女厕|卫生间|厕所|女士|洗手间	women’s room|bathroom|lavatory|restroom|room|toilet|wc|woman|women’s
🚻	0	卫生间|WC|厕所|洗手间	restroom|bathroom|lavatory|toilet|wc
🚼	0	宝宝|婴儿|换尿片|母婴室	baby symbol|baby|changing|symbol
🚾	0	厕所|卫生间|洗手间|盥洗室	water closet|bathroom|closet|lavatory|restroom|toilet|water|wc
🛂	0	护照检查|安检|护照|检查|通行证	passport control|control|passport
🛃	0	海关|行李打包	customs|packing
🛄	0	提取行李|提取|旅行|行李	baggage claim|arrived|baggage|bags|case|checked|claim|journey|packing|plane|ready|travel|trip
🛅	0	寄存行李|储物柜|寄存|行李	left luggage|baggage|case|left|locker|luggage
⚠️	0	警告|小心	warning|caution
🚸	0	儿童过街|交通|安全|指示牌|行人	children crossing|child|children|crossing|pedestrian|traffic
⛔	0	禁止通行|交通|禁止入内|禁行|请勿入内|请勿驶入	no entry|do|entry|fail|forbidden|no|not|pass|prohibited|traffic
🚫	0	禁止|不准|不许|严禁|禁入|禁行|阻止	prohibited|entry|forbidden|no|not|smoke
🚳	0	禁止自行车|严禁|交通|禁止|禁行自行车|自行车|非机动车	no bicycles|bicycle|bicycles|bike|forbidden|no|not|prohibited
🚭	0	禁止吸烟|严禁|吸烟|抽烟|禁止|禁烟	no smoking|forbidden|no|not|prohibited|smoke|smoking
🚯	0	禁止乱扔垃圾|严禁|垃圾|禁丢垃圾|禁止	no littering|forbidden|litter|littering|no|not|prohibited
🚱	0	非饮用水|水|禁止用水|节约用水|非直饮水	non-potable water|dry|non-drinking|non-potable|prohibited|water
🚷	0	禁止行人通行|严禁|行人	no pedestrians|forbidden|no|not|pedestrian|pedestrians|prohibited
📵	0	禁止使用手机|严禁|手机|电话|禁止	no mobile phones|cell|forbidden|mobile|no|not|phone|phones|prohibited|telephone
🔞	0	18禁|儿童不宜|未成年人不宜|禁止	no one under eighteen|18|age|eighteen|forbidden|no|not|one|prohibited|restriction|underage
☢️	0	辐射|放射性|标识	radioactive|sign
☣️	0	生物危害|动物|当心感染|污染|警告	biohazard|sign
⬆️	0	向上箭头|上|北|方位|方向|标识|箭头	up arrow|arrow|cardinal|direction|north|up
↗️	0	右上箭头|东北|右上|方位|方向|标识|箭头	up-right arrow|arrow|direction|intercardinal|northeast|up-right
➡️	0	向右箭头|东|右|方向|标识|箭头	right arrow|arrow|cardinal|direction|east|right
↘️	0	右下箭头|东南|右下|方位|方向|标识|箭头	down-right arrow|arrow|direction|down-right|intercardinal|southeast
⬇️	0	向下箭头|南|向下|基本|方位|正南|箭头	down arrow|arrow|cardinal|direction|down|south
↙️	0	左下箭头|左下|方向|标识|箭头|西南	down-left arrow|arrow|direction|down-left|intercardinal|southwest
⬅️	0	向左箭头|左|方向|标识|箭头|西	left arrow|arrow|cardinal|direction|left|west
↖️	0	左上箭头|左上|方向|标识|箭头|西北	up-left arrow|arrow|direction|intercardinal|northwest|up-left
↕️	0	上下箭头|上下|箭头	up-down arrow|arrow|up-down
↔️	0	左右箭头|左右|箭头	left-right arrow|arrow|left-right
↩️	0	右转弯箭头|右转弯|向左弯曲的右箭头|箭头	right arrow curving left|arrow|curving|left|right
↪️	0	左转弯箭头|向右弯曲的左箭头|左转弯|箭头	left arrow curving right|arrow|curving|left|right
⤴️	0	右上弯箭头|右上弯|向上弯曲的右箭头|箭头	right arrow curving up|arrow|curving|right|up
⤵️	0	右下弯箭头|右下弯|向下弯曲的右箭头|箭头	right arrow curving down|arrow|curving|down|right
🔃	0	顺时针垂直箭头|刷新|垂直顺时针箭头|方向|标识|箭头|重新载入|顺时针|顺时针箭头	clockwise vertical arrows|arrow|arrows|clockwise|refresh|reload|vertical
🔄	0	逆时针箭头按钮|倒转|再次|刷新|箭头|逆时针|逆时针箭头	counterclockwise arrows button|again|anticlockwise|arrow|arrows|button|counterclockwise|deja|refresh|rewindershins|vu
🔙	0	返回箭头|回退|箭头|返回	back arrow|arrow|back
🔚	0	结束箭头|箭头|终点|结束	end arrow|arrow|end
🔛	0	ON! 箭头|ON|开始|标识|箭头	on! arrow|arrow|mark|on!
🔜	0	SOON 箭头|在路上|立刻回来|箭头|马上	soon arrow|arrow|brb|omw|soon
🔝	0	置顶|向上|标识|顶	top arrow|arrow|homie|top|up
🛐	0	宗教场所|地点|宗教|崇拜|敬神|礼拜|祈祷	place of worship|place|pray|religion|worship
⚛️	0	原子符号|原子|无神论|物质	atom symbol|atheist|atom|symbol
🕉️	0	奥姆|印度|印度教|唵|宗教	om|hindu|religion
✡️	0	六芒星|六角星|大卫之星|大卫星|宗教|犹太|犹太教	star of david|david|jew|jewish|judaism|religion|star
☸️	0	法轮|佛|宗教|舵|轮盘|达摩	wheel of dharma|buddhist|dharma|religion|wheel
☯️	0	阴阳|太极|宗教|道|道教|阳|阴	yin yang|difficult|lives|religion|tao|taoist|total|yang|yin|yinyang
✝️	0	十字架|基督|天主教|宗教	latin cross|christ|christian|cross|latin|religion
☦️	0	东正教十字架|东正教|十字架|基督|宗教|正教会十字	orthodox cross|christian|cross|orthodox|religion
☪️	0	星月|伊斯兰|宗教|斋戒月|穆斯林	star and crescent|crescent|islam|muslim|ramadan|religion|star
☮️	0	和平符号|和平	peace symbol|healing|peace|peaceful|symbol
🕎	0	烛台|光明节|宗教|灯台|犹太|犹太教	menorah|candelabrum|candlestick|hanukkah|jewish|judaism|religion
🔯	0	带中间点的六芒星|六芒星|六芒星加圆点|六角星|命运|犹太|犹太教	dotted six-pointed star|dotted|fortune|jewish|judaism|six-pointed|star
🪯	0	坎达|信仰|卡尔萨|善业与佩剑得胜|坎达长剑|宗教|锡克|锡克教|锡克教徒	khanda|deg|fateh|khalsa|khanda|religion|sikh|sikhism|tegh
♈	0	白羊座|公羊|星座|牡羊座	aries|horoscope|ram|zodiac
♉	0	金牛座|公牛|星座|金牛	taurus|bull|horoscope|ox|zodiac
♊	0	双子座|双子|孪生子|星座	gemini|horoscope|twins|zodiac
♋	0	巨蟹座|巨蟹|星座|螃蟹	cancer|crab|horoscope|zodiac
♌	0	狮子座|星座|雄狮	leo|horoscope|lion|zodiac
♍	0	处女座|室女座|星座|黄道十二宫	virgo|horoscope|zodiac
♎	0	天秤座|平衡|星座|正义	libra|balance|horoscope|justice|scales|zodiac
♏	0	天蝎座|天蝎|星座|蝎子	scorpio|horoscope|scorpion|scorpius|zodiac
♐	0	射手座|人马座|射手|弓箭手|星座	sagittarius|archer|horoscope|zodiac
♑	0	摩羯座|天宫图|山羊|摩羯|星座	capricorn|goat|horoscope|zodiac
♒	0	水瓶座|星座|水	aquarius|bearer|horoscope|water|zodiac
♓	0	双鱼座|双鱼|星座|鱼	pisces|fish|horoscope|zodiac
⛎	0	蛇夫座|星座|蛇|蛇夫	ophiuchus|bearer|serpent|snake|zodiac
🔀	0	随机播放音轨按钮|交叉|打乱|随机|随机播放	shuffle tracks button|arrow|button|crossed|shuffle|tracks
🔁	0	重复按钮|循环|循环播放|箭头|顺时针	repeat button|arrow|button|clockwise|repeat
🔂	0	重复一次按钮|单曲循环|循环|箭头|顺时针	repeat single button|arrow|button|clockwise|once|repeat|single
▶️	0	播放按钮|三角|右|向右|播放|箭头	play button|arrow|button|play|right|triangle
⏩	0	快进按钮|双箭头|向前|快进|快速	fast-forward button|arrow|button|double|fast|fast-forward|forward
⏭️	0	下一个音轨按钮|三角|下一个|下一曲|下一首|往后|箭头	next track button|arrow|button|next|scene|track|triangle
⏯️	0	播放或暂停按钮|三角|向右|播放|播放或暂停|暂停	play or pause button|arrow|button|pause|play|right|triangle
◀️	0	倒退按钮|三角|倒转|后退|向左|左	reverse button|arrow|button|left|reverse|triangle
⏪	0	快退按钮|倒回|双箭头|快退|快速倒带	fast reverse button|arrow|button|double|fast|reverse|rewind
⏮️	0	上一个音轨按钮|三角|上一个|上一曲|上一首|箭头	last track button|arrow|button|last|previous|scene|track|triangle
🔼	0	向上三角形按钮|上|向上|向上按钮|往上|箭头	upwards button|arrow|button|red|up|upwards
⏫	0	快速上升按钮|上|双箭头|向上|快速向上	fast up button|arrow|button|double|fast|up
🔽	0	向下三角形按钮|下|向下|向下按钮|往下|箭头	downwards button|arrow|button|down|downwards|red
⏬	0	快速下降按钮|下|双箭头|向下|快速向下	fast down button|arrow|button|double|down|fast
⏸️	0	暂停按钮|停止|双条形|暂停	pause button|bar|button|double|pause|vertical
⏹️	0	停止按钮|停止|方形|正方形|终止	stop button|button|square|stop
⏺️	0	录制按钮|制作|圆|录像|录制|录音	record button|button|circle|record
⏏️	0	推出按钮|向上三角|弹出	eject button|button|eject
🎦	0	电影院|剧院|场所|影片|摄影机|电影	cinema|camera|film|movie
🔅	0	低亮度按钮|亮度|低|低亮度|昏暗|暗	dim button|brightness|button|dim|low
🔆	0	高亮度按钮|亮|亮度|太阳|明亮|高亮度	bright button|bright|brightness|button|light
📶	0	信号强度条|信号|天线|强度|手机|条	antenna bars|antenna|bar|bars|cell|communication|mobile|phone|signal|telephone
🛜	0	无线|Wi-Fi|WLAN|互联网|宽带|智能手机|热点|电脑|网络|计算机|连接	wireless|broadband|computer|connectivity|hotspot|internet|network|router|smartphone|wi-fi|wifi|wlan
📳	0	振动模式|手机|振动|震动	vibration mode|cell|communication|mobile|mode|phone|telephone|vibration
📴	0	手机关机|关机|关闭|关闭手机|手机	mobile phone off|cell|mobile|off|phone|telephone
♀️	0	女性符号|符号|雌性	female sign|female|sign|woman
♂️	0	男性符号|符号|雄性	male sign|male|man|sign
⚧️	0	跨性别符号|跨性别	transgender symbol|symbol|transgender
✖️	0	乘|x|乘号|取消|相乘|符号	multiply|×|cancel|multiplication|sign|x
➕	0	加|加号|十字|数学|相加|符号	plus|+
➖	0	减|减号|数学|横线|符号	minus|-|−|heavy|math|sign
➗	0	除|数学|相除|符号|除号	divide|÷|division|heavy|math|sign
🟰	0	粗等号|回答|平等|数学|相等|等于|等号|答案	heavy equals sign|answer|equal|equality|equals|heavy|math|sign
♾️	0	无穷大|宇宙|无尽|极大	infinity|forever|unbounded|universal
‼️	0	双感叹号|！|！！|两个|双叹号|叹号|吃惊|标点符号	double exclamation mark|!|!!|bangbang|double|exclamation|mark|punctuation
⁉️	0	感叹疑问号|！|！？|？|叹号|叹号加问号|吃惊|标点符号|疑问惊叹号|问号	exclamation question mark|!|!?|?|exclamation|interrobang|mark|punctuation|question
❓	0	红色问号|为什么|标点|标点符号|疑问|问号	red question mark|?|mark|punctuation|question|red
❔	0	白色问号|？|为什么|标点符号|空心|空心问号|问号|问题	white question mark|?|mark|outlined|punctuation|question|white
❕	0	白色感叹号|！|叹号|吃惊|标点符号|白色叹号|空心|空心叹号	white exclamation mark|!|exclamation|mark|outlined|punctuation|white
❗	0	红色感叹号|！|叹号|吃惊|惊讶|感叹|感叹号|标点符号	red exclamation mark|!|exclamation|mark|punctuation|red
〰️	0	波浪型破折号|标点符号|波浪线|浪花|象声号	wavy dash|dash|punctuation|wavy
💱	0	货币兑换|兑换|外汇|换汇|汇率|流通|银行	currency exchange|bank|currency|exchange|money
💲	0	粗美元符号|现金|美元|美元符号|美刀|货币|金钱	heavy dollar sign|billion|cash|charge|currency|dollar|heavy|million|money|pay|sign
⚕️	0	医疗标志|医学|医疗|蛇杖|阿斯克勒庇俄斯|阿斯克勒庇俄斯蛇杖	medical symbol|aesculapius|medical|medicine|staff|symbol
♻️	0	回收标志|再利用|再生|回收|循环	recycling symbol|recycle|recycling|symbol
⚜️	0	百合花饰|鸢尾花	fleur-de-lis|knights
🔱	0	三叉戟徽章|三叉戟|工具|波塞冬|船|锚	trident emblem|anchor|emblem|poseidon|ship|tool|trident
📛	0	姓名牌|名牌|徽章|胸牌|证章	name badge|badge|name
🔰	0	日本新手驾驶标志|V 型臂章|V形图案|人字形图记|军警|叶状|实习|新手|箭尾	japanese symbol for beginner|beginner|chevron|green|japanese|leaf|symbol|tool|yellow
⭕	0	红色空心圆圈|0|O形|圆圈|大|大圆圈|红|零	hollow red circle|circle|heavy|hollow|large|o|red
✅	0	勾号按钮|勾|勾号|完成|打勾|按钮|绿色打勾	check mark button|✓|button|check|checked|checkmark|complete|completed|done|fixed|mark|tick
☑️	0	勾选框|做好|勾号|勾选|复选框|带勾方格|打勾|搞定|选票	check box with check|✓|ballot|box|check|checked|done|off|tick
✔️	0	勾号|对勾|打勾|正确|符号	check mark|✓|check|checked|checkmark|done|heavy|mark|tick
❌	0	叉号|x|乘|交叉|取消|相乘|符号	cross mark|×|cancel|cross|mark|multiplication|multiply|x
❎	0	叉号按钮|乘|乘号|叉|取消|方形	cross mark button|×|button|cross|mark|multiplication|multiply|square|x
➰	0	卷曲环|单环|日本单环标志|标志	curly loop|curl|curly|loop
➿	0	双卷曲环|免费电话|双环|日本免费电话标志|标志	double curly loop|curl|curly|double|loop
〽️	0	庵点|开始歌唱|歌记号|符号	part alternation mark|alternation|mark|part
✳️	0	八轮辐星号|八芒星|星号	eight-spoked asterisk|*|asterisk|eight-spoked
✴️	0	八角星|星|符号	eight-pointed star|*|eight-pointed|star
❇️	0	火花|烟火|闪光|闪耀	sparkle|*
©️	0	版权	copyright|c
®️	0	注册|注册标记	registered|r
™️	0	商标|产品|标志	trade mark|mark|tm|trade|trademark
#️⃣	0	按键: #|按键	keycap: #|keycap
*️⃣	0	按键: *|按键	keycap: *|keycap
0️⃣	0	按键: 0|0|按键	keycap: 0|0|keycap|zero
1️⃣	0	按键: 1|1|一|按键	keycap: 1|1|keycap|one
2️⃣	0	按键: 2|2|二|按键	keycap: 2|2|keycap|two
3️⃣	0	按键: 3|3|三|按键	keycap: 3|3|keycap|three
4️⃣	0	按键: 4|4|四|按键	keycap: 4|4|four|keycap
5️⃣	0	按键: 5|5|五|按键	keycap: 5|5|five|keycap
6️⃣	0	按键: 6|6|六|按键	keycap: 6|6|keycap|six
7️⃣	0	按键: 7|7|七|按键	keycap: 7|7|keycap|seven
8️⃣	0	按键: 8|8|八|按键	keycap: 8|8|eight|keycap
9️⃣	0	按键: 9|9|九|按键	keycap: 9|9|keycap|nine
🔟	0	按键: 10|按键	keycap: 10|keycap
🔠	0	输入大写拉丁字母|ABCD|大写字母|大写字母键|字母|打字|拉丁文|输入法	input latin uppercase|abcd|input|latin|letters|uppercase
🔡	0	输入小写拉丁字母|abcd|小写字母|小写字母键|打字|拉丁文|输入小写字母|输入法	input latin lowercase|abcd|input|latin|letters|lowercase
🔢	0	输入数字|1234|打字|数字	input numbers|1234|input|numbers
🔣	0	输入符号|字符|打字|符号	input symbols|&|%|♪|〒|input|symbols
🔤	0	输入拉丁字母|abc|字母|打字|拉丁字母|拉丁字母键|拉丁文|输入字母	input latin letters|abc|alphabet|input|latin|letters
🅰️	0	A型血|a|字母a|按钮|血型|血液	a button (blood type)|blood|button|type
🆎	0	AB型血|ab|字母ab|按钮|血型|血液	ab button (blood type)|ab|blood|button|type
🅱️	0	B型血|b|B|按钮|血型|血液	b button (blood type)|b|blood|button|type
🆑	0	CL按钮|cl|手机|清理|清除	cl button|button|cl
🆒	0	cool按钮|cool|按键|酷	cool button|button|cool
🆓	0	免费按钮|free|不收费|免费|按钮|自由	free button|button|free
ℹ️	0	信息|信息中心|查询|资料	information|i
🆔	0	ID按钮|id|按键|识别|身份	id button|button|id|identity
Ⓜ️	0	圆圈包围的M|m|圈|字母|米	circled m|circle|circled|m
🆕	0	new按钮|按键|新|新的	new button|button|new
🆖	0	NG按钮|ng|按钮|按键|花絮	ng button|button|ng
🅾️	0	O 型血|o|O型血|字母o|按钮|血型|血液	o button (blood type)|blood|button|o|type
🆗	0	OK按钮|OK|ok按钮|同意|按键	ok button|button|ok|okay
🅿️	0	停车按钮|p|停车|按键|泊车	p button|button|p|parking
🆘	0	SOS按钮|sos|SOS|按键|救命|求救|求救钮	sos button|button|help|sos
🆙	0	up按钮|up|向上|按键	up! button|button|mark|up|up!
🆚	0	VS按钮|vs|VS|对|对决|按键	vs button|button|versus|vs
🈁	0	日文的“这里”按钮|koko|按键|日文|日语|此处|片假名|这里	japanese “here” button|button|here|japanese|katakana
🈂️	0	日文的“服务费”按钮|sa|按键|收费|日文|日文sa|日语|服务|服务费|片假名	japanese “service charge” button|button|charge|japanese|katakana|service
🈷️	0	日文的“月总量”按钮|按键|日文|日本|月|月度|统计|表意文字	japanese “monthly amount” button|amount|button|ideograph|japanese|monthly
🈶	0	日文的“收费”按钮|按键|日文|日本|有|有料|表意文字|要收费|费用	japanese “not free of charge” button|button|charge|free|ideograph|japanese|not
🈯	0	日文的“预留”按钮|保留|指|按键|日文|日本|表意文字|预定|预订	japanese “reserved” button|button|ideograph|japanese|reserved
🉐	0	日文的“议价”按钮|得|按键|日文|日本|表意文字|讨价还价	japanese “bargain” button|bargain|button|ideograph|japanese
🈹	0	日文的“打折”按钮|割|打折|折扣|按键|日文|日本|表意文字	japanese “discount” button|button|discount|ideograph|japanese
🈚	0	日文的“免费”按钮|免费|免钱|按键|无|日文|日本|表意文字	japanese “free of charge” button|button|charge|free|ideograph|japanese
🈲	0	日文的“禁止”按钮|严禁|按键|日文|日本|禁|表意文字	japanese “prohibited” button|button|ideograph|japanese|prohibited
🉑	0	日文的“可接受”按钮|可|可接受|按键|日文|日本|表意文字|许可	japanese “acceptable” button|acceptable|button|ideograph|japanese
🈸	0	日文的“申请”按钮|日文|日本|日语|申|申请|申请书|申请表|表意文字	japanese “application” button|application|button|ideograph|japanese
🈴	0	日文的“合格”按钮|及格|合|按键|日文|日本|表意文字|过关|通过	japanese “passing grade” button|button|grade|ideograph|japanese|passing
🈳	0	日文的“有空位”按钮|日文|日本|日语|有空位|空|空位|空闲|表意文字	japanese “vacancy” button|button|ideograph|japanese|vacancy
㊗️	0	日文的“祝贺”按钮|庆贺|按键|日文|日本|祝|祝福|祝贺|表意文字	japanese “congratulations” button|button|congratulations|ideograph|japanese
㊙️	0	日文的“秘密”按钮|保密|按键|日文|日本|秘|秘密|表意文字	japanese “secret” button|button|ideograph|japanese|secret
🈺	0	日文的“开始营业”按钮|开门|按键|日文|日本|营|营业|营业中|表意文字	japanese “open for business” button|business|button|ideograph|japanese|open
🈵	0	日文的“没有空位”按钮|座位|按键|日文|日本|满|表意文字	japanese “no vacancy” button|button|ideograph|japanese|no|vacancy
🔴	0	红色圆|几何|圆|圈|红|红圈|红色	red circle|circle|geometric|red
🟠	0	橙色圆|圆|圆圈|圈|橙	orange circle|circle|orange
🟡	0	黄色圆|圆|圈|黄|黄色|黄色圆圈	yellow circle|circle|yellow
🟢	0	绿色圆|圆|圆圈|圈|绿	green circle|circle|green
🔵	0	蓝色圆|圆|圈|蓝|蓝圈	blue circle|blue|circle|geometric
🟣	0	紫色圆|圆|圆圈|圈|紫|紫色|紫色圆圈	purple circle|circle|purple
🟤	0	棕色圆|圆|圆圈|圈|棕	brown circle|brown|circle
⚫	0	黑色圆|圆|圈|黑	black circle|black|circle|geometric
⚪	0	白色圆|圆|圈|白|白圈	white circle|circle|geometric|white
🟥	0	红色方块|方块|方框|正方形|红|红色	red square|card|penalty|red|square
🟧	0	橙色方块|方块|方框|橙|橙色|正方形	orange square|orange|square
🟨	0	黄色方块|方块|方框|正方形|黄|黄色	yellow square|card|penalty|square|yellow
🟩	0	绿色方块|方块|方框|正方形|绿|绿色	green square|green|square
🟦	0	蓝色方块|方块|方框|正方形|蓝|蓝色	blue square|blue|square
🟪	0	紫色方块|方块|方框|正方形|紫|紫色	purple square|purple|square
🟫	0	棕色方块|方块|方框|棕|棕色|正方形	brown square|brown|square
⬛	0	黑线大方框|大|方形|正方形|黑色|黑色大方形	black large square|black|geometric|large|square
⬜	0	白线大方框|大|方形|正方形|白色|白色方块	white large square|geometric|large|square|white
◼️	0	黑色中方块|中等|几何|方形|正方形|黑色	black medium square|black|geometric|medium|square
◻️	0	白色中方块|中等|方形|正方形|白色	white medium square|geometric|medium|square|white
◾	0	黑色中小方块|中小|方形|正方形|黑色	black medium-small square|black|geometric|medium-small|square
◽	0	白色中小方块|中小 正方形|几何|方形|白色	white medium-small square|geometric|medium-small|square|white
▪️	0	黑色小方块|几何|几何图形|小|方形|正方形|黑色	black small square|black|geometric|small|square
▫️	0	白色小方块|小|方形|正方形|白色	white small square|geometric|small|square|white
🔶	0	橙色大菱形|大|方块|方片|橘色方块|橘黄色|橙色方块|菱形|钻石	large orange diamond|diamond|geometric|large|orange
🔷	0	蓝色大菱形|大|方块|方片|菱形|蓝色|钻石	large blue diamond|blue|diamond|geometric|large
🔸	0	橙色小菱形|小|方块|方片|橘色方块|橘黄色|菱形	small orange diamond|diamond|geometric|orange|small
🔹	0	蓝色小菱形|小|方片|菱形|蓝色|蓝色方块|钻石	small blue diamond|blue|diamond|geometric|small
🔺	0	红色正三角|三角形|向上|正三角|红色	red triangle pointed up|geometric|pointed|red|triangle|up
🔻	0	红色倒三角|三角形|下|倒三角|向下|红色	red triangle pointed down|down|geometric|pointed|red|triangle
💠	0	带圆点的菱形|中心|内部|圆|方块|方块内有点|梅花形|菱形	diamond with a dot|comic|diamond|dot|geometric
🔘	0	单选按钮|单独|单选钮|圆心|按钮|按键|选中	radio button|button|geometric|radio
🔳	0	白色方形按钮|按钮|方形|白线方形按钮|白线正方形按钮|白色正方形按钮|白边线方形按钮|白边线正方形按钮	white square button|button|geometric|outlined|square|white
🔲	0	黑色方形按钮|几何|几何图形|按钮|方形|黑线方形按钮|黑线正方形按钮|黑色正方形按钮|黑边线方形按钮|黑边线正方形按钮	black square button|black|button|geometric|square
🏁	0	黑白方格旗|方格|格子旗|竞赛|终点|终点旗|黑白方格	chequered flag|checkered|chequered|finish|flag|flags|game|race|racing|sport|win
🚩	0	三角旗|升旗|旗|旗杆上的三角旗|旗杆上的旗帜|红色旗帜|高尔夫	triangular flag|construction|flag|golf|post|triangular
🎌	0	交叉旗|对叉|旗|旗帜|日本	crossed flags|celebration|cross|crossed|flags|japanese
🏴	0	黑旗|举黑旗|摇黑棋|黑色旗|黑色旗子|黑色旗帜	black flag|black|flag|waving
🏳️	0	白旗|举白旗|摇白旗|白色旗子|白色旗帜	white flag|flag|waving|white
🏳️‍🌈	0	彩虹旗|双性|同性|多色|彩虹|旗|旗帜|跨性别	rainbow flag|bisexual|flag|gay|genderqueer|glbt|glbtq|lesbian|lgbt|lgbtq|lgbtqia|pride|queer|rainbow|trans|transgender
🏳️‍⚧️	0	跨性别旗|旗帜|浅蓝色|白色|粉红色|跨性别	transgender flag|blue|flag|light|pink|transgender|white
🏴‍☠️	0	海盗旗|掠夺|海上|财宝|骷髅	pirate flag|flag|jolly|pirate|plunder|roger|treasure
🇦🇨	0	旗: 阿森松岛|旗	flag: ascension island|flag
🇦🇩	0	旗: 安道尔|旗	flag: andorra|flag
🇦🇪	0	旗: 阿拉伯联合酋长国|旗	flag: united arab emirates|flag
🇦🇫	0	旗: 阿富汗|旗	flag: afghanistan|flag
🇦🇬	0	旗: 安提瓜和巴布达|旗	flag: antigua & barbuda|flag
🇦🇮	0	旗: 安圭拉|旗	flag: anguilla|flag
🇦🇱	0	旗: 阿尔巴尼亚|旗	flag: albania|flag
🇦🇲	0	旗: 亚美尼亚|旗	flag: armenia|flag
🇦🇴	0	旗: 安哥拉|旗	flag: angola|flag
🇦🇶	0	旗: 南极洲|旗	flag: antarctica|flag
🇦🇷	0	旗: 阿根廷|旗	flag: argentina|flag
🇦🇸	0	旗: 美属萨摩亚|旗	flag: american samoa|flag
🇦🇹	0	旗: 奥地利|旗	flag: austria|flag
🇦🇺	0	旗: 澳大利亚|旗	flag: australia|flag
🇦🇼	0	旗: 阿鲁巴|旗	flag: aruba|flag
🇦🇽	0	旗: 奥兰群岛|旗	flag: åland islands|flag
🇦🇿	0	旗: 阿塞拜疆|旗	flag: azerbaijan|flag
🇧🇦	0	旗: 波斯尼亚和黑塞哥维那|旗	flag: bosnia & herzegovina|flag
🇧🇧	0	旗: 巴巴多斯|旗	flag: barbados|flag
🇧🇩	0	旗: 孟加拉国|旗	flag: bangladesh|flag
🇧🇪	0	旗: 比利时|旗	flag: belgium|flag
🇧🇫	0	旗: 布基纳法索|旗	flag: burkina faso|flag
🇧🇬	0	旗: 保加利亚|旗	flag: bulgaria|flag
🇧🇭	0	旗: 巴林|旗	flag: bahrain|flag
🇧🇮	0	旗: 布隆迪|旗	flag: burundi|flag
🇧🇯	0	旗: 贝宁|旗	flag: benin|flag
🇧🇱	0	旗: 圣巴泰勒米|旗	flag: st. barthélemy|flag
🇧🇲	0	旗: 百慕大|旗	flag: bermuda|flag
🇧🇳	0	旗: 文莱|旗	flag: brunei|flag
🇧🇴	0	旗: 玻利维亚|旗	flag: bolivia|flag
🇧🇶	0	旗: 荷属加勒比区|旗	flag: caribbean netherlands|flag
🇧🇷	0	旗: 巴西|旗	flag: brazil|flag
🇧🇸	0	旗: 巴哈马|旗	flag: bahamas|flag
🇧🇹	0	旗: 不丹|旗	flag: bhutan|flag
🇧🇻	0	旗: 布韦岛|旗	flag: bouvet island|flag
🇧🇼	0	旗: 博茨瓦纳|旗	flag: botswana|flag
🇧🇾	0	旗: 白俄罗斯|旗	flag: belarus|flag
🇧🇿	0	旗: 伯利兹|旗	flag: belize|flag
🇨🇦	0	旗: 加拿大|旗	flag: canada|flag
🇨🇨	0	旗: 科科斯（基林）群岛|旗	flag: cocos (keeling) islands|flag
🇨🇩	0	旗: 刚果（金）|旗	flag: congo - kinshasa|flag
🇨🇫	0	旗: 中非共和国|旗	flag: central african republic|flag
🇨🇬	0	旗: 刚果（布）|旗	flag: congo - brazzaville|flag
🇨🇭	0	旗: 瑞士|旗	flag: switzerland|flag
🇨🇮	0	旗: 科特迪瓦|旗	flag: côte d’ivoire|flag
🇨🇰	0	旗: 库克群岛|旗	flag: cook islands|flag
🇨🇱	0	旗: 智利|旗	flag: chile|flag
🇨🇲	0	旗: 喀麦隆|旗	flag: cameroon|flag
🇨🇳	0	旗: 中国|旗	flag: china|flag
🇨🇴	0	旗: 哥伦比亚|旗	flag: colombia|flag
🇨🇵	0	旗: 克利珀顿岛|旗	flag: clipperton island|flag
🇨🇷	0	旗: 哥斯达黎加|旗	flag: costa rica|flag
🇨🇺	0	旗: 古巴|旗	flag: cuba|flag
🇨🇻	0	旗: 佛得角|旗	flag: cape verde|flag
🇨🇼	0	旗: 库拉索|旗	flag: curaçao|flag
🇨🇽	0	旗: 圣诞岛|旗	flag: christmas island|flag
🇨🇾	0	旗: 塞浦路斯|旗	flag: cyprus|flag
🇨🇿	0	旗: 捷克|旗	flag: czechia|flag
🇩🇪	0	旗: 德国|旗	flag: germany|flag
🇩🇬	0	旗: 迪戈加西亚岛|旗	flag: diego garcia|flag
🇩🇯	0	旗: 吉布提|旗	flag: djibouti|flag
🇩🇰	0	旗: 丹麦|旗	flag: denmark|flag
🇩🇲	0	旗: 多米尼克|旗	flag: dominica|flag
🇩🇴	0	旗: 多米尼加共和国|旗	flag: dominican republic|flag
🇩🇿	0	旗: 阿尔及利亚|旗	flag: algeria|flag
🇪🇦	0	旗: 休达及梅利利亚|旗	flag: ceuta & melilla|flag
🇪🇨	0	旗: 厄瓜多尔|旗	flag: ecuador|flag
🇪🇪	0	旗: 爱沙尼亚|旗	flag: estonia|flag
🇪🇬	0	旗: 埃及|旗	flag: egypt|flag
🇪🇭	0	旗: 西撒哈拉|旗	flag: western sahara|flag
🇪🇷	0	旗: 厄立特里亚|旗	flag: eritrea|flag
🇪🇸	0	旗: 西班牙|旗	flag: spain|flag
🇪🇹	0	旗: 埃塞俄比亚|旗	flag: ethiopia|flag
🇪🇺	0	旗: 欧盟|旗	flag: european union|flag
🇫🇮	0	旗: 芬兰|旗	flag: finland|flag
🇫🇯	0	旗: 斐济|旗	flag: fiji|flag
🇫🇰	0	旗: 福克兰群岛|旗	flag: falkland islands|flag
🇫🇲	0	旗: 密克罗尼西亚|旗	flag: micronesia|flag
🇫🇴	0	旗: 法罗群岛|旗	flag: faroe islands|flag
🇫🇷	0	旗: 法国|旗	flag: france|flag
🇬🇦	0	旗: 加蓬|旗	flag: gabon|flag
🇬🇧	0	旗: 英国|旗	flag: united kingdom|flag
🇬🇩	0	旗: 格林纳达|旗	flag: grenada|flag
🇬🇪	0	旗: 格鲁吉亚|旗	flag: georgia|flag
🇬🇫	0	旗: 法属圭亚那|旗	flag: french guiana|flag
🇬🇬	0	旗: 根西岛|旗	flag: guernsey|flag
🇬🇭	0	旗: 加纳|旗	flag: ghana|flag
🇬🇮	0	旗: 直布罗陀|旗	flag: gibraltar|flag
🇬🇱	0	旗: 格陵兰|旗	flag: greenland|flag
🇬🇲	0	旗: 冈比亚|旗	flag: gambia|flag
🇬🇳	0	旗: 几内亚|旗	flag: guinea|flag
🇬🇵	0	旗: 瓜德罗普|旗	flag: guadeloupe|flag
🇬🇶	0	旗: 赤道几内亚|旗	flag: equatorial guinea|flag
🇬🇷	0	旗: 希腊|旗	flag: greece|flag
🇬🇸	0	旗: 南乔治亚和南桑威奇群岛|旗	flag: south georgia & south sandwich islands|flag
🇬🇹	0	旗: 危地马拉|旗	flag: guatemala|flag
🇬🇺	0	旗: 关岛|旗	flag: guam|flag
🇬🇼	0	旗: 几内亚比绍|旗	flag: guinea-bissau|flag
🇬🇾	0	旗: 圭亚那|旗	flag: guyana|flag
🇭🇰	0	旗: 中国香港特别行政区|旗	flag: hong kong sar china|flag
🇭🇲	0	旗: 赫德岛和麦克唐纳群岛|旗	flag: heard & mcdonald islands|flag
🇭🇳	0	旗: 洪都拉斯|旗	flag: honduras|flag
🇭🇷	0	旗: 克罗地亚|旗	flag: croatia|flag
🇭🇹	0	旗: 海地|旗	flag: haiti|flag
🇭🇺	0	旗: 匈牙利|旗	flag: hungary|flag
🇮🇨	0	旗: 加纳利群岛|旗	flag: canary islands|flag
🇮🇩	0	旗: 印度尼西亚|旗	flag: indonesia|flag
🇮🇪	0	旗: 爱尔兰|旗	flag: ireland|flag
🇮🇱	0	旗: 以色列|旗	flag: israel|flag
🇮🇲	0	旗: 马恩岛|旗	flag: isle of man|flag
🇮🇳	0	旗: 印度|旗	flag: india|flag
🇮🇴	0	旗: 英属印度洋领地|旗	flag: british indian ocean territory|flag
🇮🇶	0	旗: 伊拉克|旗	flag: iraq|flag
🇮🇷	0	旗: 伊朗|旗	flag: iran|flag
🇮🇸	0	旗: 冰岛|旗	flag: iceland|flag
🇮🇹	0	旗: 意大利|旗	flag: italy|flag
🇯🇪	0	旗: 泽西岛|旗	flag: jersey|flag
🇯🇲	0	旗: 牙买加|旗	flag: jamaica|flag
🇯🇴	0	旗: 约旦|旗	flag: jordan|flag
🇯🇵	0	旗: 日本|旗	flag: japan|flag
🇰🇪	0	旗: 肯尼亚|旗	flag: kenya|flag
🇰🇬	0	旗: 吉尔吉斯斯坦|旗	flag: kyrgyzstan|flag
🇰🇭	0	旗: 柬埔寨|旗	flag: cambodia|flag
🇰🇮	0	旗: 基里巴斯|旗	flag: kiribati|flag
🇰🇲	0	旗: 科摩罗|旗	flag: comoros|flag
🇰🇳	0	旗: 圣基茨和尼维斯|旗	flag: st. kitts & nevis|flag
🇰🇵	0	旗: 朝鲜|旗	flag: north korea|flag
🇰🇷	0	旗: 韩国|旗	flag: south korea|flag
🇰🇼	0	旗: 科威特|旗	flag: kuwait|flag
🇰🇾	0	旗: 开曼群岛|旗	flag: cayman islands|flag
🇰🇿	0	旗: 哈萨克斯坦|旗	flag: kazakhstan|flag
🇱🇦	0	旗: 老挝|旗	flag: laos|flag
🇱🇧	0	旗: 黎巴嫩|旗	flag: lebanon|flag
🇱🇨	0	旗: 圣卢西亚|旗	flag: st. lucia|flag
🇱🇮	0	旗: 列支敦士登|旗	flag: liechtenstein|flag
🇱🇰	0	旗: 斯里兰卡|旗	flag: sri lanka|flag
🇱🇷	0	旗: 利比里亚|旗	flag: liberia|flag
🇱🇸	0	旗: 莱索托|旗	flag: lesotho|flag
🇱🇹	0	旗: 立陶宛|旗	flag: lithuania|flag
🇱🇺	0	旗: 卢森堡|旗	flag: luxembourg|flag
🇱🇻	0	旗: 拉脱维亚|旗	flag: latvia|flag
🇱🇾	0	旗: 利比亚|旗	flag: libya|flag
🇲🇦	0	旗: 摩洛哥|旗	flag: morocco|flag
🇲🇨	0	旗: 摩纳哥|旗	flag: monaco|flag
🇲🇩	0	旗: 摩尔多瓦|旗	flag: moldova|flag
🇲🇪	0	旗: 黑山|旗	flag: montenegro|flag
🇲🇫	0	旗: 法属圣马丁|旗	flag: st. martin|flag
🇲🇬	0	旗: 马达加斯加|旗	flag: madagascar|flag
🇲🇭	0	旗: 马绍尔群岛|旗	flag: marshall islands|flag
🇲🇰	0	旗: 北马其顿|旗	flag: north macedonia|flag
🇲🇱	0	旗: 马里|旗	flag: mali|flag
🇲🇲	0	旗: 缅甸|旗	flag: myanmar (burma)|flag
🇲🇳	0	旗: 蒙古|旗	flag: mongolia|flag
🇲🇴	0	旗: 中国澳门特别行政区|旗	flag: macao sar china|flag
🇲🇵	0	旗: 北马里亚纳群岛|旗	flag: northern mariana islands|flag
🇲🇶	0	旗: 马提尼克|旗	flag: martinique|flag
🇲🇷	0	旗: 毛里塔尼亚|旗	flag: mauritania|flag
🇲🇸	0	旗: 蒙特塞拉特|旗	flag: montserrat|flag
🇲🇹	0	旗: 马耳他|旗	flag: malta|flag
🇲🇺	0	旗: 毛里求斯|旗	flag: mauritius|flag
🇲🇻	0	旗: 马尔代夫|旗	flag: maldives|flag
🇲🇼	0	旗: 马拉维|旗	flag: malawi|flag
🇲🇽	0	旗: 墨西哥|旗	flag: mexico|flag
🇲🇾	0	旗: 马来西亚|旗	flag: malaysia|flag
🇲🇿	0	旗: 莫桑比克|旗	flag: mozambique|flag
🇳🇦	0	旗: 纳米比亚|旗	flag: namibia|flag
🇳🇨	0	旗: 新喀里多尼亚|旗	flag: new caledonia|flag
🇳🇪	0	旗: 尼日尔|旗	flag: niger|flag
🇳🇫	0	旗: 诺福克岛|旗	flag: norfolk island|flag
🇳🇬	0	旗: 尼日利亚|旗	flag: nigeria|flag
🇳🇮	0	旗: 尼加拉瓜|旗	flag: nicaragua|flag
🇳🇱	0	旗: 荷兰|旗	flag: netherlands|flag
🇳🇴	0	旗: 挪威|旗	flag: norway|flag
🇳🇵	0	旗: 尼泊尔|旗	flag: nepal|flag
🇳🇷	0	旗: 瑙鲁|旗	flag: nauru|flag
🇳🇺	0	旗: 纽埃|旗	flag: niue|flag
🇳🇿	0	旗: 新西兰|旗	flag: new zealand|flag
🇴🇲	0	旗: 阿曼|旗	flag: oman|flag
🇵🇦	0	旗: 巴拿马|旗	flag: panama|flag
🇵🇪	0	旗: 秘鲁|旗	flag: peru|flag
🇵🇫	0	旗: 法属波利尼西亚|旗	flag: french polynesia|flag
🇵🇬	0	旗: 巴布亚新几内亚|旗	flag: papua new guinea|flag
🇵🇭	0	旗: 菲律宾|旗	flag: philippines|flag
🇵🇰	0	旗: 巴基斯坦|旗	flag: pakistan|flag
🇵🇱	0	旗: 波兰|旗	flag: poland|flag
🇵🇲	0	旗: 圣皮埃尔和密克隆群岛|旗	flag: st. pierre & miquelon|flag
🇵🇳	0	旗: 皮特凯恩群岛|旗	flag: pitcairn islands|flag
🇵🇷	0	旗: 波多黎各|旗	flag: puerto rico|flag
🇵🇸	0	旗: 巴勒斯坦领土|旗	flag: palestinian territories|flag
🇵🇹	0	旗: 葡萄牙|旗	flag: portugal|flag
🇵🇼	0	旗: 帕劳|旗	flag: palau|flag
🇵🇾	0	旗: 巴拉圭|旗	flag: paraguay|flag
🇶🇦	0	旗: 卡塔尔|旗	flag: qatar|flag
🇷🇪	0	旗: 留尼汪|旗	flag: réunion|flag
🇷🇴	0	旗: 罗马尼亚|旗	flag: romania|flag
🇷🇸	0	旗: 塞尔维亚|旗	flag: serbia|flag
🇷🇺	0	旗: 俄罗斯|旗	flag: russia|flag
🇷🇼	0	旗: 卢旺达|旗	flag: rwanda|flag
🇸🇦	0	旗: 沙特阿拉伯|旗	flag: saudi arabia|flag
🇸🇧	0	旗: 所罗门群岛|旗	flag: solomon islands|flag
🇸🇨	0	旗: 塞舌尔|旗	flag: seychelles|flag
🇸🇩	0	旗: 苏丹|旗	flag: sudan|flag
🇸🇪	0	旗: 瑞典|旗	flag: sweden|flag
🇸🇬	0	旗: 新加坡|旗	flag: singapore|flag
🇸🇭	0	旗: 圣赫勒拿|旗	flag: st. helena|flag
🇸🇮	0	旗: 斯洛文尼亚|旗	flag: slovenia|flag
🇸🇯	0	旗: 斯瓦尔巴和扬马延|旗	flag: svalbard & jan mayen|flag
🇸🇰	0	旗: 斯洛伐克|旗	flag: slovakia|flag
🇸🇱	0	旗: 塞拉利昂|旗	flag: sierra leone|flag
🇸🇲	0	旗: 圣马力诺|旗	flag: san marino|flag
🇸🇳	0	旗: 塞内加尔|旗	flag: senegal|flag
🇸🇴	0	旗: 索马里|旗	flag: somalia|flag
🇸🇷	0	旗: 苏里南|旗	flag: suriname|flag
🇸🇸	0	旗: 南苏丹|旗	flag: south sudan|flag
🇸🇹	0	旗: 圣多美和普林西比|旗	flag: são tomé & príncipe|flag
🇸🇻	0	旗: 萨尔瓦多|旗	flag: el salvador|flag
🇸🇽	0	旗: 荷属圣马丁|旗	flag: sint maarten|flag
🇸🇾	0	旗: 叙利亚|旗	flag: syria|flag
🇸🇿	0	旗: 斯威士兰|旗	flag: eswatini|flag
🇹🇦	0	旗: 特里斯坦-达库尼亚群岛|旗	flag: tristan da cunha|flag
🇹🇨	0	旗: 特克斯和凯科斯群岛|旗	flag: turks & caicos islands|flag
🇹🇩	0	旗: 乍得|旗	flag: chad|flag
🇹🇫	0	旗: 法属南部领地|旗	flag: french southern territories|flag
🇹🇬	0	旗: 多哥|旗	flag: togo|flag
🇹🇭	0	旗: 泰国|旗	flag: thailand|flag
🇹🇯	0	旗: 塔吉克斯坦|旗	flag: tajikistan|flag
🇹🇰	0	旗: 托克劳|旗	flag: tokelau|flag
🇹🇱	0	旗: 东帝汶|旗	flag: timor-leste|flag
🇹🇲	0	旗: 土库曼斯坦|旗	flag: turkmenistan|flag
🇹🇳	0	旗: 突尼斯|旗	flag: tunisia|flag
🇹🇴	0	旗: 汤加|旗	flag: tonga|flag
🇹🇷	0	旗: 土耳其|旗	flag: türkiye|flag
🇹🇹	0	旗: 特立尼达和多巴哥|旗	flag: trinidad & tobago|flag
🇹🇻	0	旗: 图瓦卢|旗	flag: tuvalu|flag
🇹🇼	0	旗: 台湾|旗	flag: taiwan|flag
🇹🇿	0	旗: 坦桑尼亚|旗	flag: tanzania|flag
🇺🇦	0	旗: 乌克兰|旗	flag: ukraine|flag
🇺🇬	0	旗: 乌干达|旗	flag: uganda|flag
🇺🇲	0	旗: 美国本土外小岛屿|旗	flag: u.s. outlying islands|flag
🇺🇳	0	旗: 联合国|旗	flag: united nations|flag
🇺🇸	0	旗: 美国|旗	flag: united states|flag
🇺🇾	0	旗: 乌拉圭|旗	flag: uruguay|flag
🇺🇿	0	旗: 乌兹别克斯坦|旗	flag: uzbekistan|flag
🇻🇦	0	旗: 梵蒂冈|旗	flag: vatican city|flag
🇻🇨	0	旗: 圣文森特和格林纳丁斯|旗	flag: st. vincent & grenadines|flag
🇻🇪	0	旗: 委内瑞拉|旗	flag: venezuela|flag
🇻🇬	0	旗: 英属维尔京群岛|旗	flag: british virgin islands|flag
🇻🇮	0	旗: 美属维尔京群岛|旗	flag: u.s. virgin islands|flag
🇻🇳	0	旗: 越南|旗	flag: vietnam|flag
🇻🇺	0	旗: 瓦努阿图|旗	flag: vanuatu|flag
🇼🇫	0	旗: 瓦利斯和富图纳|旗	flag: wallis & futuna|flag
🇼🇸	0	旗: 萨摩亚|旗	flag: samoa|flag
🇽🇰	0	旗: 科索沃|旗	flag: kosovo|flag
🇾🇪	0	旗: 也门|旗	flag: yemen|flag
🇾🇹	0	旗: 马约特|旗	flag: mayotte|flag
🇿🇦	0	旗: 南非|旗	flag: south africa|flag
🇿🇲	0	旗: 赞比亚|旗	flag: zambia|flag
🇿🇼	0	旗: 津巴布韦|旗	flag: zimbabwe|flag
🏴󠁧󠁢󠁥󠁮󠁧󠁿	0	旗: 英格兰|旗	flag: england|flag
🏴󠁧󠁢󠁳󠁣󠁴󠁿	0	旗: 苏格兰|旗	flag: scotland|flag
🏴󠁧󠁢󠁷󠁬󠁳󠁿	0	旗: 威尔士|旗	flag: wales|flag
"""
}
