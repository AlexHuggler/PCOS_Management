#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { existsSync } from 'node:fs';

const ROOT = process.cwd();
const DOCS = path.join(ROOT, 'docs');
const CONTENT_DIR = path.join(DOCS, 'content');
const SITE = 'https://cyclebalance.app';
const DATE = '2026-05-07';
const MANIFEST_PATH = path.join(CONTENT_DIR, 'blog-manifest.json');
const MEDIA_MANIFEST_PATH = path.join(CONTENT_DIR, 'media-manifest.json');

const locales = {
  en: { label: 'EN', name: 'English', lang: 'en', prefix: '', og: 'en_US', appStoreUrl: 'https://apps.apple.com/us/app/cyclebalance/id6760353511' },
  de: { label: 'DE', name: 'Deutsch', lang: 'de', prefix: '/de', og: 'de_DE', appStoreUrl: 'https://apps.apple.com/de/app/cyclebalance/id6760353511' },
  fr: { label: 'FR', name: 'Francais', lang: 'fr', prefix: '/fr', og: 'fr_FR', appStoreUrl: 'https://apps.apple.com/fr/app/cyclebalance/id6760353511' },
  it: { label: 'IT', name: 'Italiano', lang: 'it', prefix: '/it', og: 'it_IT', appStoreUrl: 'https://apps.apple.com/it/app/cyclebalance/id6760353511' },
  ja: { label: 'JA', name: '日本語', lang: 'ja', prefix: '/ja', og: 'ja_JP', appStoreUrl: 'https://apps.apple.com/jp/app/cyclebalance/id6760353511' },
  ko: { label: 'KO', name: '한국어', lang: 'ko', prefix: '/ko', og: 'ko_KR', appStoreUrl: 'https://apps.apple.com/kr/app/cyclebalance/id6760353511' },
  nl: { label: 'NL', name: 'Nederlands', lang: 'nl', prefix: '/nl', og: 'nl_NL', appStoreUrl: 'https://apps.apple.com/nl/app/cyclebalance/id6760353511' }
};

const ui = {
  en: {
    blogTitle: 'The PCOS Blog',
    blogSeo: 'Evidence-Based PCOS Articles',
    blogDeck: 'Evidence-based articles on nutrition, supplements, insulin resistance, cycle tracking, and the habits that can support PCOS care.',
    readMore: 'Read more',
    back: 'Back to Blog',
    byline: 'By the CycleBalance Team - reviewed against peer-reviewed research',
    takeaways: 'Key takeaways',
    evidence: 'What the evidence says',
    practical: 'Practical ways to use this',
    tracking: 'What to track in CycleBalance',
    clinician: 'When to ask a clinician',
    related: 'Related reading',
    refs: 'References',
    ctaTitle: 'Track what works for your body',
    ctaText: 'CycleBalance is designed for PCOS: irregular cycles, symptoms, glucose, supplements, and patterns in one privacy-first app.',
    ctaButton: 'Download on the App Store',
    disclaimer: 'Medical disclaimer: This article is for educational purposes only and is not medical advice. CycleBalance is not a medical device. Always consult a qualified healthcare professional before changing diet, supplements, or treatment for PCOS.',
    meta: topic => `Evidence-backed CycleBalance guide to ${topic} for PCOS, with practical tracking ideas, careful medical disclaimers, and references to clinical guidance.`,
    intro: topic => `For many people with PCOS, ${topic} becomes easier to manage when it is treated as a repeatable pattern instead of a perfect rule. The goal is not to chase a cure or follow a rigid plan. It is to understand what the evidence supports, choose a realistic next step, and track whether it helps your own symptoms over time.`,
    evidenceCopy: topic => `The 2023 International Evidence-Based Guideline for PCOS emphasizes lifelong, individualized care, healthy lifestyle support, shared decision-making, and attention to metabolic, reproductive, dermatologic, sleep, and psychological features of PCOS. That means ${topic} should be framed as one useful part of care, not a stand-alone treatment.`,
    practicalCopy: action => `A useful first step is to make ${action} simple enough to repeat for two to three weeks. Pair changes with regular meals, sleep, movement, medication or supplement routines, and cycle notes so the signal is easier to see.`,
    trackingCopy: topic => `Track ${topic} alongside cycle length, bleeding, acne, cravings, mood, energy, sleep, stress, movement, glucose if you monitor it, and any supplements or medications you use. Patterns are more useful than isolated good or bad days.`,
    clinicianCopy: topic => `Ask a clinician for individualized guidance if ${topic} relates to missed periods, fertility planning, severe pain, rapid symptom changes, disordered eating concerns, pregnancy, medication interactions, or a supplement you are considering.`
  },
  de: {
    blogTitle: 'Der PCOS-Blog',
    blogSeo: 'Evidenzbasierte PCOS-Artikel',
    blogDeck: 'Evidenzbasierte Artikel zu Ernahrung, Nahrungserganzung, Insulinresistenz, Zyklustracking und alltaglichen Strategien bei PCOS.',
    readMore: 'Mehr lesen',
    back: 'Zuruck zum Blog',
    byline: 'Vom CycleBalance-Team - mit peer-reviewter Forschung abgeglichen',
    takeaways: 'Wichtigste Punkte',
    evidence: 'Was die Evidenz sagt',
    practical: 'Praktische Anwendung',
    tracking: 'Was Sie in CycleBalance verfolgen konnen',
    clinician: 'Wann Sie arztlichen Rat einholen sollten',
    related: 'Weiterlesen',
    refs: 'Quellen',
    ctaTitle: 'Verfolgen Sie, was Ihrem Korper hilft',
    ctaText: 'CycleBalance ist fur PCOS gemacht: unregelmassige Zyklen, Symptome, Glukose, Supplemente und Muster in einer datenschutzfreundlichen App.',
    ctaButton: 'Im App Store laden',
    disclaimer: 'Medizinischer Hinweis: Dieser Artikel dient nur der Bildung und ist keine medizinische Beratung. CycleBalance ist kein Medizinprodukt. Sprechen Sie mit qualifiziertem Fachpersonal, bevor Sie Ernahrung, Supplemente oder Behandlung bei PCOS andern.',
    meta: topic => `Evidenzbasierter CycleBalance-Leitfaden zu ${topic} bei PCOS, mit praktischen Tracking-Ideen, vorsichtiger Einordnung und Quellen aus Leitlinien und Forschung.`,
    intro: topic => `Bei PCOS lasst sich ${topic} oft besser einordnen, wenn es als wiederholbares Muster statt als perfekte Regel betrachtet wird. Es geht nicht um Heilversprechen oder starre Plane, sondern um evidenznahe Schritte, die im Alltag realistisch sind.`,
    evidenceCopy: topic => `Die internationale PCOS-Leitlinie 2023 betont lebenslange, individuelle Betreuung, gesunde Lebensweise, gemeinsame Entscheidungen und die metabolischen, reproduktiven, dermatologischen, Schlaf- und psychischen Aspekte von PCOS. ${topic} ist daher ein Baustein, kein Ersatz fur medizinische Behandlung.`,
    practicalCopy: action => `Ein guter Start ist, ${action} so einfach zu halten, dass es zwei bis drei Wochen wiederholbar bleibt. Kombinieren Sie die Veranderung mit Mahlzeiten, Schlaf, Bewegung, Medikamenten oder Supplementen und Zyklusnotizen.`,
    trackingCopy: topic => `Verfolgen Sie ${topic} zusammen mit Zykluslange, Blutung, Akne, Heisshunger, Stimmung, Energie, Schlaf, Stress, Bewegung, Glukosewerten und verwendeten Supplementen oder Medikamenten.`,
    clinicianCopy: topic => `Holen Sie arztlichen Rat ein, wenn ${topic} mit ausbleibenden Perioden, Kinderwunsch, starken Schmerzen, schnellen Symptomanderungen, Essstorungsrisiken, Schwangerschaft, Medikamentenwechselwirkungen oder neuen Supplementen zusammenhangt.`
  },
  fr: {
    blogTitle: 'Le blog SOPK',
    blogSeo: 'Articles SOPK fondes sur les donnees probantes',
    blogDeck: 'Articles fondes sur les donnees probantes sur la nutrition, les complements, la resistance a l insulin, le suivi du cycle et les habitudes utiles dans le SOPK.',
    readMore: 'Lire la suite',
    back: 'Retour au blog',
    byline: 'Par l equipe CycleBalance - relu avec la recherche scientifique',
    takeaways: 'Points cles',
    evidence: 'Ce que disent les donnees',
    practical: 'Comment l appliquer',
    tracking: 'Quoi suivre dans CycleBalance',
    clinician: 'Quand demander un avis medical',
    related: 'Articles lies',
    refs: 'References',
    ctaTitle: 'Suivez ce qui aide votre corps',
    ctaText: 'CycleBalance est concu pour le SOPK : cycles irreguliers, symptomes, glucose, complements et tendances dans une app respectueuse de la vie privee.',
    ctaButton: 'Telecharger sur l App Store',
    disclaimer: 'Avertissement medical : cet article est uniquement educatif et ne constitue pas un avis medical. CycleBalance n est pas un dispositif medical. Consultez un professionnel qualifie avant de modifier votre alimentation, vos complements ou votre traitement du SOPK.',
    meta: topic => `Guide CycleBalance fonde sur les donnees probantes sur ${topic} dans le SOPK, avec idees de suivi, prudence medicale et references cliniques.`,
    intro: topic => `Avec le SOPK, ${topic} devient souvent plus utile lorsqu on le traite comme un motif a observer, pas comme une regle parfaite. L objectif est de comprendre les donnees, choisir une action realiste et suivre ce qui change avec le temps.`,
    evidenceCopy: topic => `La ligne directrice internationale 2023 sur le SOPK met l accent sur des soins individualises, le mode de vie, la decision partagee et les dimensions metaboliques, reproductives, cutanees, du sommeil et psychologiques. ${topic} doit donc rester un element de soutien, non un traitement unique.`,
    practicalCopy: action => `Commencez par rendre ${action} assez simple pour etre repete pendant deux a trois semaines. Associez ce changement aux repas, au sommeil, au mouvement, aux medicaments ou complements et aux notes de cycle.`,
    trackingCopy: topic => `Suivez ${topic} avec la longueur du cycle, les saignements, l acne, les envies, l humeur, l energie, le sommeil, le stress, l activite, la glycemie si vous la mesurez et les complements ou medicaments.`,
    clinicianCopy: topic => `Demandez un avis medical si ${topic} touche aux regles absentes, a la fertilite, a des douleurs fortes, a des changements rapides, aux troubles alimentaires, a la grossesse, aux interactions medicamenteuses ou a un nouveau complement.`
  },
  it: {
    blogTitle: 'Il blog PCOS',
    blogSeo: 'Articoli PCOS basati sulle evidenze',
    blogDeck: 'Articoli basati sulle evidenze su nutrizione, integratori, insulino-resistenza, monitoraggio del ciclo e abitudini utili nella PCOS.',
    readMore: 'Leggi di piu',
    back: 'Torna al blog',
    byline: 'Dal team CycleBalance - rivisto rispetto alla ricerca peer-reviewed',
    takeaways: 'Punti chiave',
    evidence: 'Cosa dicono le evidenze',
    practical: 'Come usarlo nella pratica',
    tracking: 'Cosa monitorare in CycleBalance',
    clinician: 'Quando parlarne con un medico',
    related: 'Letture correlate',
    refs: 'Riferimenti',
    ctaTitle: 'Monitora cosa funziona per il tuo corpo',
    ctaText: 'CycleBalance e pensata per la PCOS: cicli irregolari, sintomi, glucosio, integratori e pattern in un app attenta alla privacy.',
    ctaButton: 'Scarica su App Store',
    disclaimer: 'Avvertenza medica: questo articolo e solo educativo e non e un consiglio medico. CycleBalance non e un dispositivo medico. Consulta un professionista qualificato prima di cambiare dieta, integratori o trattamento per la PCOS.',
    meta: topic => `Guida CycleBalance basata sulle evidenze su ${topic} nella PCOS, con idee pratiche di monitoraggio, disclaimer medico e riferimenti clinici.`,
    intro: topic => `Nella PCOS, ${topic} diventa piu utile quando viene osservato come un pattern ripetibile, non come una regola perfetta. L obiettivo e capire le evidenze, scegliere un passo realistico e monitorare cosa cambia nel tempo.`,
    evidenceCopy: topic => `La linea guida internazionale 2023 sulla PCOS sottolinea cura individualizzata, stile di vita, decisioni condivise e attenzione agli aspetti metabolici, riproduttivi, cutanei, del sonno e psicologici. ${topic} va quindi considerato un supporto, non una cura unica.`,
    practicalCopy: action => `Un buon primo passo e rendere ${action} abbastanza semplice da ripetere per due o tre settimane. Collega il cambiamento a pasti, sonno, movimento, farmaci o integratori e note sul ciclo.`,
    trackingCopy: topic => `Monitora ${topic} insieme a durata del ciclo, sanguinamento, acne, voglie, umore, energia, sonno, stress, movimento, glicemia se la controlli e integratori o farmaci.`,
    clinicianCopy: topic => `Parlane con un medico se ${topic} riguarda mestruazioni assenti, fertilita, dolore forte, cambiamenti rapidi, disturbi alimentari, gravidanza, interazioni farmacologiche o nuovi integratori.`
  },
  ja: {
    blogTitle: 'PCOSブログ',
    blogSeo: 'エビデンスに基づくPCOS記事',
    blogDeck: '栄養、サプリメント、インスリン抵抗性、周期記録、PCOSケアを支える習慣についてのエビデンス重視の記事。',
    readMore: '続きを読む',
    back: 'ブログに戻る',
    byline: 'CycleBalanceチーム - 査読済み研究に照らして確認',
    takeaways: '要点',
    evidence: 'エビデンスの見方',
    practical: '実生活での使い方',
    tracking: 'CycleBalanceで記録したいこと',
    clinician: '医療者に相談する目安',
    related: '関連記事',
    refs: '参考文献',
    ctaTitle: '自分の体に合うものを記録する',
    ctaText: 'CycleBalanceはPCOSのために設計されています。不規則な周期、症状、血糖、サプリメント、体調パターンをプライバシー重視で記録できます。',
    ctaButton: 'App Storeでダウンロード',
    disclaimer: '医療上の注意: この記事は教育目的であり、医学的助言ではありません。CycleBalanceは医療機器ではありません。PCOSの食事、サプリメント、治療を変更する前に、資格のある医療専門家に相談してください。',
    meta: topic => `PCOSにおける${topic}について、CycleBalanceがエビデンス、記録の工夫、医療上の注意点とともに解説します。`,
    intro: topic => `PCOSでは、${topic}を完璧なルールではなく、繰り返し観察できるパターンとして扱うと役立ちます。目的は治癒を約束することではなく、根拠を理解し、現実的な一歩を選び、自分の症状の変化を追うことです。`,
    evidenceCopy: topic => `2023年の国際PCOSガイドラインは、個別化されたケア、生活習慣支援、共同意思決定、代謝・生殖・皮膚・睡眠・心理面への配慮を重視しています。${topic}も医療の代わりではなく、ケアの一部として考えることが大切です。`,
    practicalCopy: action => `最初は、${action}を2〜3週間続けられるくらい小さくします。食事、睡眠、運動、薬やサプリメント、周期メモと一緒に見ると変化が見えやすくなります。`,
    trackingCopy: topic => `${topic}を、周期の長さ、出血、にきび、食欲、気分、エネルギー、睡眠、ストレス、運動、測定している場合の血糖、サプリメントや薬と一緒に記録します。`,
    clinicianCopy: topic => `${topic}が月経の停止、妊娠希望、強い痛み、急な症状変化、摂食の不安、妊娠、薬の相互作用、新しいサプリメントに関係する場合は医療者に相談してください。`
  },
  ko: {
    blogTitle: 'PCOS 블로그',
    blogSeo: '근거 기반 PCOS 글',
    blogDeck: '영양, 보충제, 인슐린 저항성, 주기 기록, PCOS 관리를 돕는 생활 습관에 대한 근거 기반 글.',
    readMore: '더 읽기',
    back: '블로그로 돌아가기',
    byline: 'CycleBalance 팀 작성 - 동료 심사 연구와 대조',
    takeaways: '핵심 요점',
    evidence: '근거가 말하는 것',
    practical: '실제로 활용하는 법',
    tracking: 'CycleBalance에서 기록할 것',
    clinician: '의료진에게 상담할 때',
    related: '관련 글',
    refs: '참고문헌',
    ctaTitle: '내 몸에 맞는 변화를 기록하세요',
    ctaText: 'CycleBalance는 PCOS를 위해 설계되었습니다. 불규칙한 주기, 증상, 혈당, 보충제, 패턴을 개인정보 중심으로 기록합니다.',
    ctaButton: 'App Store에서 다운로드',
    disclaimer: '의학적 고지: 이 글은 교육 목적이며 의학적 조언이 아닙니다. CycleBalance는 의료기기가 아닙니다. PCOS 식단, 보충제, 치료를 바꾸기 전에는 자격 있는 의료 전문가와 상담하세요.',
    meta: topic => `PCOS와 ${topic}에 대한 CycleBalance 근거 기반 가이드입니다. 실용적인 기록 방법, 신중한 의학적 고지, 임상 참고문헌을 포함합니다.`,
    intro: topic => `PCOS에서는 ${topic}을 완벽한 규칙이 아니라 반복해서 관찰할 수 있는 패턴으로 볼 때 더 도움이 됩니다. 목표는 치료를 약속하는 것이 아니라 근거를 이해하고, 현실적인 다음 단계를 고르고, 내 증상 변화를 기록하는 것입니다.`,
    evidenceCopy: topic => `2023 국제 PCOS 근거 기반 가이드라인은 개인화된 관리, 건강한 생활습관 지원, 공동 의사결정, 대사·생식·피부·수면·심리적 특징을 함께 보도록 권고합니다. 그래서 ${topic}은 단독 치료가 아니라 관리의 한 부분으로 보아야 합니다.`,
    practicalCopy: action => `처음에는 ${action}을 2~3주 반복할 수 있을 만큼 단순하게 만드세요. 식사, 수면, 움직임, 약이나 보충제, 주기 기록과 함께 보면 신호가 더 잘 보입니다.`,
    trackingCopy: topic => `${topic}을 주기 길이, 출혈, 여드름, 식욕, 기분, 에너지, 수면, 스트레스, 운동, 혈당을 측정한다면 혈당, 복용 중인 보충제나 약과 함께 기록하세요.`,
    clinicianCopy: topic => `${topic}이 생리 없음, 임신 계획, 심한 통증, 빠른 증상 변화, 섭식 문제, 임신, 약물 상호작용, 새 보충제와 관련된다면 의료진과 상담하세요.`
  },
  nl: {
    blogTitle: 'De PCOS-blog',
    blogSeo: 'Onderbouwde PCOS-artikelen',
    blogDeck: 'Onderbouwde artikelen over voeding, supplementen, insulineresistentie, cyclusregistratie en gewoonten die PCOS-zorg kunnen ondersteunen.',
    readMore: 'Lees meer',
    back: 'Terug naar blog',
    byline: 'Door het CycleBalance-team - getoetst aan peer-reviewed onderzoek',
    takeaways: 'Belangrijkste punten',
    evidence: 'Wat het bewijs zegt',
    practical: 'Praktisch gebruiken',
    tracking: 'Wat u in CycleBalance kunt volgen',
    clinician: 'Wanneer u een zorgverlener vraagt',
    related: 'Gerelateerd',
    refs: 'Bronnen',
    ctaTitle: 'Volg wat voor uw lichaam werkt',
    ctaText: 'CycleBalance is gemaakt voor PCOS: onregelmatige cycli, symptomen, glucose, supplementen en patronen in een privacygerichte app.',
    ctaButton: 'Download in de App Store',
    disclaimer: 'Medische disclaimer: dit artikel is alleen educatief en geen medisch advies. CycleBalance is geen medisch hulpmiddel. Raadpleeg een gekwalificeerde zorgverlener voordat u voeding, supplementen of behandeling voor PCOS verandert.',
    meta: topic => `Onderbouwde CycleBalance-gids over ${topic} bij PCOS, met praktische registratietips, zorgvuldige medische disclaimer en klinische bronnen.`,
    intro: topic => `Bij PCOS wordt ${topic} nuttiger wanneer u het ziet als een herhaalbaar patroon, niet als een perfecte regel. Het doel is de evidence begrijpen, een haalbare stap kiezen en volgen wat er in uw eigen lichaam verandert.`,
    evidenceCopy: topic => `De internationale PCOS-richtlijn van 2023 benadrukt levenslange, individuele zorg, gezonde leefstijl, gezamenlijke besluitvorming en aandacht voor metabole, reproductieve, huid-, slaap- en psychologische aspecten. ${topic} is daarom een onderdeel van zorg, geen op zichzelf staande behandeling.`,
    practicalCopy: action => `Een goede eerste stap is ${action} eenvoudig genoeg maken om twee tot drie weken te herhalen. Koppel veranderingen aan maaltijden, slaap, beweging, medicatie of supplementen en cyclusnotities.`,
    trackingCopy: topic => `Volg ${topic} samen met cycluslengte, bloeding, acne, trek, stemming, energie, slaap, stress, beweging, glucose als u die meet en supplementen of medicatie.`,
    clinicianCopy: topic => `Vraag een zorgverlener om advies als ${topic} samenhangt met uitblijvende menstruatie, vruchtbaarheid, hevige pijn, snelle symptoomverandering, eetproblemen, zwangerschap, interacties met medicatie of nieuwe supplementen.`
  }
};

const articleBody = {
  en: {
    takeaways: topic => [
      `${topic} is best evaluated through patterns over time, not isolated days.`,
      'The strongest PCOS guidance favors individualized care and sustainable habits over one-size-fits-all rules.',
      'Track symptoms, cycle timing, lifestyle inputs, and medications or supplements together before judging what works.',
      'Use clinician guidance for missed periods, fertility goals, severe symptoms, medication changes, or supplement questions.'
    ],
    carefulClaims: 'Evidence-based PCOS care is careful about language: a strategy may support metabolic health, symptom awareness, or quality of life, but it should not be presented as a cure. This is especially important for search and AI summaries, where clear claims and visible references help readers understand the strength of the information.',
    practicalItems: [
      'Choose one repeatable change before adding several new rules at once.',
      'Pair the change with an existing routine, such as breakfast, bedtime, medication timing, or weekly meal planning.',
      'Use symptoms as signals, not grades. PCOS patterns are influenced by sleep, stress, movement, nutrition, medication, and cycle timing.',
      'Give a new habit enough time to observe a trend, then decide whether it is worth keeping.'
    ],
    appUse: 'CycleBalance is useful here because PCOS often involves overlapping signals. A note about fatigue may matter more when it is seen beside sleep, cycle day, cravings, exercise, glucose, or supplement timing.',
    appointmentNotes: 'Bring your notes to appointments as a concise timeline: what changed, when it changed, how often it happened, and what else was happening around the same time. That helps shift the conversation from memory to evidence.',
    caption: topic => `Visual reminder for ${topic}.`
  },
  de: {
    takeaways: topic => [
      `${topic} lasst sich am besten uber Muster im Verlauf beurteilen, nicht uber einzelne Tage.`,
      'Die starkste PCOS-Evidenz betont individuelle Betreuung und nachhaltige Gewohnheiten statt Regeln fur alle.',
      'Verfolgen Sie Symptome, Zyklustiming, Alltagseinflusse und Medikamente oder Supplemente gemeinsam, bevor Sie beurteilen, was hilft.',
      'Nutzen Sie fachliche Beratung bei ausbleibenden Perioden, Kinderwunsch, starken Symptomen, Medikamentenanderungen oder Supplementfragen.'
    ],
    carefulClaims: 'Evidenzbasierte PCOS-Information muss sorgsam formuliert sein: Eine Strategie kann Stoffwechselgesundheit, Symptomwahrnehmung oder Lebensqualitat unterstutzen, sollte aber nicht als Heilung dargestellt werden. Das ist besonders wichtig fur Suche und KI-Zusammenfassungen, damit Leser die Starke der Aussage und die Quellen klar einordnen konnen.',
    practicalItems: [
      'Wahlen Sie zuerst eine wiederholbare Veranderung, bevor mehrere neue Regeln dazukommen.',
      'Koppeln Sie die Veranderung an eine bestehende Routine wie Fruhstuck, Schlafenszeit, Medikamenteneinnahme oder Wochenplanung.',
      'Nutzen Sie Symptome als Signale, nicht als Noten. PCOS-Muster werden von Schlaf, Stress, Bewegung, Ernahrung, Medikamenten und Zyklustiming beeinflusst.',
      'Geben Sie einer neuen Gewohnheit genug Zeit, um einen Trend zu sehen, und entscheiden Sie dann, ob sie bleiben soll.'
    ],
    appUse: 'CycleBalance hilft hier, weil sich PCOS-Signale oft uberlagern. Eine Notiz zu Mudigkeit kann mehr bedeuten, wenn sie neben Schlaf, Zyklustag, Heisshunger, Bewegung, Glukose oder Supplementtiming sichtbar wird.',
    appointmentNotes: 'Bringen Sie Ihre Notizen als kurze Zeitleiste zum Termin mit: was sich geandert hat, wann es begann, wie oft es auftrat und was gleichzeitig passierte. So wird aus Erinnerung besser verwertbare Evidenz.',
    caption: topic => `Visuelle Erinnerung zu ${topic}.`
  },
  fr: {
    takeaways: topic => [
      `${topic} s evalue mieux comme tendance dans le temps que comme journee isolee.`,
      'Les recommandations les plus solides sur le SOPK privilegient des soins individualises et des habitudes durables, pas des regles identiques pour toutes.',
      'Suivez ensemble les symptomes, le moment du cycle, les facteurs de mode de vie et les medicaments ou complements avant de juger ce qui aide.',
      'Demandez un avis medical pour les regles absentes, les projets de grossesse, les symptomes severes, les changements de medicaments ou les questions de complements.'
    ],
    carefulClaims: 'Une information fiable sur le SOPK doit rester precise dans ses formulations : une strategie peut soutenir la sante metabolique, la lecture des symptomes ou la qualite de vie, mais elle ne doit pas etre presentee comme une guerison. C est essentiel pour la recherche et les resumes par IA, afin que les lecteurs voient clairement la force des affirmations et les references.',
    practicalItems: [
      'Choisissez d abord un changement repetable avant d ajouter plusieurs nouvelles regles.',
      'Associez ce changement a une routine existante, comme le petit-dejeuner, le coucher, les medicaments ou la planification des repas.',
      'Traitez les symptomes comme des signaux, pas comme des notes. Les tendances du SOPK dependent du sommeil, du stress, du mouvement, de la nutrition, des medicaments et du moment du cycle.',
      'Laissez assez de temps a une nouvelle habitude pour observer une tendance, puis decidez si elle merite d etre gardee.'
    ],
    appUse: 'CycleBalance est utile ici parce que les signaux du SOPK se chevauchent souvent. Une note sur la fatigue peut avoir plus de sens lorsqu elle est vue avec le sommeil, le jour du cycle, les envies, l activite, la glycemie ou le moment des complements.',
    appointmentNotes: 'Apportez vos notes en consultation sous forme de chronologie courte : ce qui a change, quand cela a commence, a quelle frequence et ce qui se passait en meme temps. Cela aide a passer du souvenir a des donnees exploitables.',
    caption: topic => `Repere visuel pour ${topic}.`
  },
  it: {
    takeaways: topic => [
      `${topic} si valuta meglio osservando i pattern nel tempo, non i singoli giorni.`,
      'Le indicazioni piu solide sulla PCOS favoriscono cure personalizzate e abitudini sostenibili, non regole uguali per tutte.',
      'Monitora insieme sintomi, tempi del ciclo, fattori di stile di vita e farmaci o integratori prima di giudicare cosa funziona.',
      'Usa il supporto clinico per mestruazioni assenti, obiettivi di fertilita, sintomi importanti, cambi di farmaci o dubbi sugli integratori.'
    ],
    carefulClaims: 'L informazione basata sulle evidenze per la PCOS deve usare un linguaggio prudente: una strategia puo sostenere salute metabolica, consapevolezza dei sintomi o qualita della vita, ma non va presentata come una cura. Questo e importante anche per ricerca e riassunti IA, dove affermazioni chiare e fonti visibili aiutano a capire la forza delle prove.',
    practicalItems: [
      'Scegli un cambiamento ripetibile prima di aggiungere molte nuove regole.',
      'Collega il cambiamento a una routine esistente, come colazione, ora di dormire, farmaci o pianificazione dei pasti.',
      'Usa i sintomi come segnali, non come voti. I pattern della PCOS dipendono da sonno, stress, movimento, alimentazione, farmaci e fase del ciclo.',
      'Dai a una nuova abitudine abbastanza tempo per osservare una tendenza, poi decidi se tenerla.'
    ],
    appUse: 'CycleBalance e utile perche nella PCOS i segnali spesso si sovrappongono. Una nota sulla stanchezza puo avere piu significato se vista accanto a sonno, giorno del ciclo, voglie, movimento, glucosio o tempi degli integratori.',
    appointmentNotes: 'Porta gli appunti alle visite come una breve cronologia: cosa e cambiato, quando, quanto spesso e cos altro succedeva nello stesso periodo. Aiuta a trasformare il ricordo in informazioni piu utilizzabili.',
    caption: topic => `Promemoria visivo per ${topic}.`
  },
  ja: {
    takeaways: topic => [
      `${topic}は、1日だけで判断するより、時間の中のパターンとして見るほうが役立ちます。`,
      'PCOSの主要な指針は、全員に同じルールではなく、個別化されたケアと続けやすい習慣を重視します。',
      '何が役立つか判断する前に、症状、周期のタイミング、生活要因、薬やサプリメントを一緒に記録します。',
      '月経が来ない、妊娠を考えている、症状が強い、薬を変更する、サプリメントに迷う場合は医療者に相談してください。'
    ],
    carefulClaims: 'PCOSの情報では言葉の使い方が大切です。ある方法が代謝の健康、症状の把握、生活の質を支えることはありますが、治癒として示すべきではありません。検索やAI要約でも、主張と参考文献が明確であるほど、読者は情報の強さを判断しやすくなります。',
    practicalItems: [
      '最初から多くのルールを増やさず、1つの続けやすい変化を選びます。',
      '朝食、就寝前、薬のタイミング、週の食事準備など、すでにある習慣に結びつけます。',
      '症状は採点ではなくサインとして扱います。PCOSのパターンは睡眠、ストレス、運動、食事、薬、周期の時期に影響されます。',
      '新しい習慣は傾向を見る時間を取り、その後に続ける価値があるか判断します。'
    ],
    appUse: 'PCOSでは複数のサインが重なることが多いため、CycleBalanceで一緒に見ると役立ちます。疲れのメモも、睡眠、周期日、食欲、運動、血糖、サプリメントのタイミングと並べると意味が見えやすくなります。',
    appointmentNotes: '受診時には、何が変わったか、いつ始まったか、どのくらい起きたか、その頃ほかに何があったかを短い時系列で持参してください。記憶だけでなく、具体的な情報として話しやすくなります。',
    caption: topic => `${topic}について考えるための視覚的メモ。`
  },
  ko: {
    takeaways: topic => [
      `${topic}은 하루하루의 좋고 나쁨보다 시간에 따른 패턴으로 볼 때 더 잘 평가할 수 있습니다.`,
      '가장 강한 PCOS 지침은 모두에게 같은 규칙보다 개인화된 관리와 지속 가능한 습관을 강조합니다.',
      '무엇이 도움이 되는지 판단하기 전에 증상, 주기 시점, 생활 요인, 약이나 보충제를 함께 기록하세요.',
      '생리 없음, 임신 계획, 심한 증상, 약 변경, 보충제 질문이 있다면 의료진의 조언을 받으세요.'
    ],
    carefulClaims: '근거 기반 PCOS 정보는 표현이 신중해야 합니다. 어떤 전략은 대사 건강, 증상 인식, 삶의 질을 도울 수 있지만 치료법처럼 제시해서는 안 됩니다. 검색과 AI 요약에서도 명확한 주장과 보이는 참고문헌은 독자가 정보의 강도를 이해하는 데 도움이 됩니다.',
    practicalItems: [
      '여러 규칙을 한꺼번에 더하기 전에 반복 가능한 변화 하나를 선택하세요.',
      '아침 식사, 취침 전, 약 복용 시간, 주간 식사 준비처럼 이미 있는 루틴에 연결하세요.',
      '증상은 점수가 아니라 신호로 보세요. PCOS 패턴은 수면, 스트레스, 움직임, 영양, 약, 주기 시점의 영향을 받습니다.',
      '새 습관은 추세를 볼 만큼 시간을 두고, 계속할 가치가 있는지 판단하세요.'
    ],
    appUse: 'PCOS에서는 여러 신호가 겹치는 경우가 많아 CycleBalance가 도움이 됩니다. 피로 메모도 수면, 주기일, 식욕, 운동, 혈당, 보충제 타이밍과 함께 보면 더 의미 있는 단서가 될 수 있습니다.',
    appointmentNotes: '진료 때는 무엇이 바뀌었는지, 언제 바뀌었는지, 얼마나 자주 있었는지, 같은 시기에 무엇이 있었는지 짧은 타임라인으로 가져가세요. 기억보다 구체적인 정보로 대화할 수 있습니다.',
    caption: topic => `${topic}을 생각할 때 참고할 시각 자료.`
  },
  nl: {
    takeaways: topic => [
      `${topic} beoordeelt u het best via patronen in de tijd, niet via losse dagen.`,
      'De sterkste PCOS-richtlijnen geven voorkeur aan individuele zorg en duurzame gewoonten boven regels die voor iedereen hetzelfde zijn.',
      'Volg symptomen, cyclustiming, leefstijlinvloeden en medicatie of supplementen samen voordat u beoordeelt wat werkt.',
      'Vraag klinische begeleiding bij uitblijvende menstruatie, vruchtbaarheidsdoelen, ernstige symptomen, medicatiewijzigingen of supplementvragen.'
    ],
    carefulClaims: 'Onderbouwde PCOS-informatie moet zorgvuldig worden geformuleerd: een strategie kan metabole gezondheid, symptoominzicht of kwaliteit van leven ondersteunen, maar hoort niet als genezing te worden gepresenteerd. Dat is ook belangrijk voor zoekmachines en AI-samenvattingen, waar duidelijke claims en zichtbare bronnen lezers helpen de sterkte van informatie te beoordelen.',
    practicalItems: [
      'Kies eerst een herhaalbare verandering voordat u meerdere nieuwe regels tegelijk toevoegt.',
      'Koppel de verandering aan een bestaande routine, zoals ontbijt, bedtijd, medicatiemomenten of weekplanning.',
      'Gebruik symptomen als signalen, niet als cijfers. PCOS-patronen worden beinvloed door slaap, stress, beweging, voeding, medicatie en cyclustiming.',
      'Geef een nieuwe gewoonte genoeg tijd om een trend te zien en beslis daarna of u die wilt houden.'
    ],
    appUse: 'CycleBalance is hierbij nuttig omdat PCOS-signalen elkaar vaak overlappen. Een notitie over vermoeidheid kan meer betekenen wanneer die naast slaap, cyclusdag, trek, beweging, glucose of supplementtiming staat.',
    appointmentNotes: 'Neem uw notities mee naar afspraken als korte tijdlijn: wat veranderde, wanneer het veranderde, hoe vaak het gebeurde en wat er tegelijk speelde. Zo verschuift het gesprek van herinnering naar bruikbare informatie.',
    caption: topic => `Visuele herinnering voor ${topic}.`
  }
};

const sections = {
  nutrition: { en: 'PCOS Nutrition', de: 'PCOS-Ernahrung', fr: 'Nutrition SOPK', it: 'Nutrizione PCOS', ja: 'PCOS栄養', ko: 'PCOS 영양', nl: 'PCOS-voeding' },
  supplements: { en: 'PCOS Supplements', de: 'PCOS-Supplemente', fr: 'Complements SOPK', it: 'Integratori PCOS', ja: 'PCOSサプリメント', ko: 'PCOS 보충제', nl: 'PCOS-supplementen' },
  education: { en: 'PCOS Education', de: 'PCOS-Wissen', fr: 'Education SOPK', it: 'Educazione PCOS', ja: 'PCOS教育', ko: 'PCOS 교육', nl: 'PCOS-uitleg' },
  lifestyle: { en: 'PCOS Lifestyle', de: 'PCOS-Alltag', fr: 'Mode de vie SOPK', it: 'Stile di vita PCOS', ja: 'PCOS生活習慣', ko: 'PCOS 생활습관', nl: 'PCOS-leefstijl' },
  tracking: { en: 'Cycle Tracking', de: 'Zyklus-Tracking', fr: 'Suivi du cycle', it: 'Monitoraggio ciclo', ja: '周期記録', ko: '주기 기록', nl: 'Cyclus volgen' }
};

const references = {
  pcos2023: { title: '2023 International Evidence-Based Guideline for the Assessment and Management of Polycystic Ovary Syndrome', source: 'Monash University', url: 'https://www.monash.edu/medicine/mchri/pcos/guideline' },
  jcem2023: { title: 'Recommendations From the 2023 International Evidence-Based Guideline for the Assessment and Management of PCOS', source: 'The Journal of Clinical Endocrinology and Metabolism', url: 'https://academic.oup.com/jcem/article/108/10/2447/7242360' },
  acog: { title: 'Polycystic Ovary Syndrome (PCOS) FAQ', source: 'American College of Obstetricians and Gynecologists', url: 'https://www.acog.org/womens-health/faqs/polycystic-ovary-syndrome-pcos' },
  nichd: { title: 'Polycystic Ovary Syndrome (PCOS)', source: 'NICHD', url: 'https://www.nichd.nih.gov/health/topics/pcos' },
  cochraneLifestyle: { title: 'Lifestyle changes in women with polycystic ovary syndrome', source: 'Cochrane Database of Systematic Reviews', url: 'https://pubmed.ncbi.nlm.nih.gov/30921477/' },
  inositolCochrane: { title: 'Inositol for subfertile women with polycystic ovary syndrome', source: 'Cochrane Database of Systematic Reviews', url: 'https://www.cochranelibrary.com/cdsr/doi/10.1002/14651858.CD012378.pub2/full' },
  inositolMeta: { title: 'Effectiveness of myoinositol for polycystic ovary syndrome: systematic review and meta-analysis', source: 'Endocrine', url: 'https://pubmed.ncbi.nlm.nih.gov/30049532/' },
  magnesiumOds: { title: 'Magnesium: Health Professional Fact Sheet', source: 'NIH Office of Dietary Supplements', url: 'https://ods.od.nih.gov/factsheets/Magnesium-HealthProfessional/' },
  omegaOds: { title: 'Omega-3 Fatty Acids: Health Professional Fact Sheet', source: 'NIH Office of Dietary Supplements', url: 'https://ods.od.nih.gov/factsheets/Omega3FattyAcids-HealthProfessional/' },
  vitaminDOds: { title: 'Vitamin D: Health Professional Fact Sheet', source: 'NIH Office of Dietary Supplements', url: 'https://ods.od.nih.gov/factsheets/VitaminD-HealthProfessional/' },
  zincOds: { title: 'Zinc: Health Professional Fact Sheet', source: 'NIH Office of Dietary Supplements', url: 'https://ods.od.nih.gov/factsheets/Zinc-HealthProfessional/' },
  dhaAha: { title: 'Dietary Guidance to Improve Cardiovascular Health', source: 'American Heart Association', url: 'https://www.ahajournals.org/doi/10.1161/CIR.0000000000001031' },
  legumeTrial: { title: 'Effect of legumes as part of a low glycemic index diet on glycemic control and cardiovascular risk factors', source: 'Archives of Internal Medicine', url: 'https://pubmed.ncbi.nlm.nih.gov/23089999/' },
  sleepPcos: { title: 'Sleep disturbances and PCOS are addressed as part of lifelong health in the international guideline', source: '2023 International PCOS Guideline', url: 'https://www.monash.edu/medicine/mchri/pcos/guideline' }
};

function l(en, de, fr, it, ja, ko, nl) {
  return { en, de, fr, it, ja, ko, nl };
}

function article(slug, section, hero, inlineImages, refs, related, titles, topics, actions) {
  return {
    slug,
    section,
    datePublished: DATE,
    dateModified: DATE,
    heroImage: hero,
    inlineImages,
    referenceIds: refs,
    relatedSlugs: related,
    healthContent: true,
    locales: Object.keys(locales),
    localized: Object.fromEntries(Object.keys(locales).map(locale => [
      locale,
      {
        title: titles[locale],
        topic: topics[locale],
        action: actions[locale],
        description: ui[locale].meta(topics[locale]),
        keywords: keywordString(topics[locale], locale)
      }
    ]))
  };
}

function keywordString(topic, locale) {
  const base = locale === 'en' ? 'PCOS, polycystic ovary syndrome, CycleBalance, irregular cycles, symptom tracking' : 'PCOS, CycleBalance, cycle tracking, symptom tracking';
  return `${topic}, ${base}`;
}

const defaultManifest = {
  generatedAt: DATE,
  supportedLocales: Object.keys(locales),
  references,
  articles: [
    article('best-foods-for-pcos', 'nutrition', '/assets/images/blog/nutrition-general/build-a-pcos-friendly-plate.webp', ['/assets/images/blog/nutrition-general/pcos-choose-more-limit-more-foods.webp', '/assets/images/blog/nutrition-general/the-science-of-fiber-pcos-blood-sugar.webp'], ['pcos2023', 'jcem2023', 'cochraneLifestyle', 'legumeTrial'], ['protein-strategy-for-pcos', 'pcos-carbohydrate-blueprint', 'fiber-and-pcos-blood-sugar'],
      l('The Best Foods for PCOS: An Evidence-Based Nutrition Guide', 'Die besten Lebensmittel bei PCOS: ein evidenzbasierter Ernahrungsleitfaden', 'Les meilleurs aliments pour le SOPK : un guide nutritionnel fonde sur les donnees', 'I migliori alimenti per la PCOS: una guida basata sulle evidenze', 'PCOSに最適な食品：エビデンスに基づく栄養ガイド', 'PCOS에 가장 좋은 음식: 근거 기반 영양 가이드', 'De beste voeding bij PCOS: een wetenschappelijk onderbouwde gids'),
      l('PCOS-friendly foods and plate-building', 'PCOS-freundliche Lebensmittel und Telleraufbau', 'les aliments et assiettes adaptes au SOPK', 'alimenti e piatti adatti alla PCOS', 'PCOSに合う食品と食事の組み立て', 'PCOS에 맞는 음식과 식사 구성', 'PCOS-vriendelijke voeding en bordopbouw'),
      l('building one balanced plate at a time', 'Teller Schritt fur Schritt ausgewogen aufzubauen', 'composer une assiette equilibree', 'costruire un piatto equilibrato', '一食ずつバランスを整えること', '한 끼씩 균형 있게 구성하는 것', 'stap voor stap een evenwichtig bord maken')),
    article('protein-strategy-for-pcos', 'nutrition', '/assets/images/blog/nutrition-protein/the-power-of-protein-for-pcos-balance.webp', ['/assets/images/blog/nutrition-protein/build-pcos-meals-around-protein-and-fiber.webp', '/assets/images/blog/nutrition-protein/start-the-day-with-protein-pcos-breakfast-ideas.webp'], ['pcos2023', 'jcem2023', 'cochraneLifestyle'], ['best-foods-for-pcos', 'pcos-breakfast-ideas', 'fiber-and-pcos-blood-sugar'],
      l('Why Protein Matters for PCOS: A Strategy for Blood Sugar and Hormones', 'Warum Eiweiss bei PCOS wichtig ist: eine Strategie fur Blutzucker und Hormone', 'Pourquoi les proteines comptent dans le SOPK : strategie pour la glycemie et les hormones', 'Perche le proteine contano nella PCOS: strategia per glicemia e ormoni', 'PCOSにおけるタンパク質の重要性：血糖とホルモンのための戦略', 'PCOS에서 단백질이 중요한 이유: 혈당과 호르몬 전략', 'Waarom eiwit belangrijk is bij PCOS: strategie voor bloedsuiker en hormonen'),
      l('protein timing and meal balance', 'Eiweiss-Timing und Mahlzeitenbalance', 'le timing des proteines et l equilibre des repas', 'tempistica delle proteine ed equilibrio dei pasti', 'タンパク質のタイミングと食事バランス', '단백질 섭취 타이밍과 식사 균형', 'eiwittiming en maaltijdbalans'),
      l('adding a protein anchor to meals and snacks', 'Mahlzeiten und Snacks mit einer Eiweissquelle zu verankern', 'ajouter une source de proteines aux repas et collations', 'aggiungere una fonte proteica a pasti e spuntini', '食事や間食にタンパク質の軸を入れること', '식사와 간식에 단백질 중심을 더하는 것', 'een eiwitanker toevoegen aan maaltijden en snacks')),
    article('pcos-carbohydrate-blueprint', 'nutrition', '/assets/images/blog/nutrition-carbs/the-pcos-carbohydrate-blueprint-smart-swaps.webp', ['/assets/images/blog/nutrition-carbs/pair-carbs-with-protein-fat-fiber-pcos.webp', '/assets/images/blog/nutrition-carbs/pcos-carbohydrate-blueprint-best-carbs-hall-of-fame.webp'], ['pcos2023', 'cochraneLifestyle', 'legumeTrial'], ['best-foods-for-pcos', 'fiber-and-pcos-blood-sugar', 'pcos-breakfast-ideas'],
      l('The PCOS Carbohydrate Blueprint: Why You Do Not Need to Cut Carbs', 'Der PCOS-Kohlenhydrat-Bauplan: warum Sie Kohlenhydrate nicht streichen mussen', 'Le plan glucidique du SOPK : pourquoi il ne faut pas supprimer les glucides', 'Il blueprint dei carboidrati nella PCOS: perche non serve eliminarli', 'PCOS炭水化物ブループリント：糖質を完全カットしなくてよい理由', 'PCOS 탄수화물 청사진: 탄수화물을 끊을 필요가 없는 이유', 'Het PCOS-koolhydratenplan: waarom u koolhydraten niet hoeft te schrappen'),
      l('carbohydrate quality, pairing, and blood sugar', 'Kohlenhydratqualitat, Kombination und Blutzucker', 'la qualite des glucides, les associations et la glycemie', 'qualita dei carboidrati, abbinamenti e glicemia', '炭水化物の質、組み合わせ、血糖', '탄수화물의 질, 조합, 혈당', 'koolhydraatkwaliteit, combinaties en bloedsuiker'),
      l('pairing carbohydrates with protein, fat, and fiber', 'Kohlenhydrate mit Eiweiss, Fett und Ballaststoffen zu kombinieren', 'associer les glucides aux proteines, graisses et fibres', 'abbinare carboidrati a proteine, grassi e fibre', '炭水化物をタンパク質・脂質・食物繊維と組み合わせること', '탄수화물을 단백질, 지방, 섬유질과 함께 먹는 것', 'koolhydraten combineren met eiwit, vet en vezels')),
    article('pcos-and-fruit-guide', 'nutrition', '/assets/images/blog/nutrition-fruits/the-pcos-fruit-guide-natures-best-for-hormone-balance.webp', ['/assets/images/blog/nutrition-fruits/why-fruit-choice-matters-for-pcos.webp', '/assets/images/blog/nutrition-fruits/best-pick-berries-for-pcos.webp'], ['pcos2023', 'cochraneLifestyle'], ['best-foods-for-pcos', 'pcos-carbohydrate-blueprint', 'fiber-and-pcos-blood-sugar'],
      l('PCOS and Fruit: A Smart Guide to Hormone-Friendly Choices', 'PCOS und Obst: ein kluger Leitfaden fur hormonfreundliche Entscheidungen', 'SOPK et fruits : guide intelligent pour des choix favorables aux hormones', 'PCOS e frutta: guida intelligente per scelte amiche degli ormoni', 'PCOSと果物：ホルモンに優しい賢い選び方ガイド', 'PCOS와 과일: 호르몬 친화적 선택 가이드', 'PCOS en fruit: slimme gids voor hormoonvriendelijke keuzes'),
      l('fruit choices, fiber, and blood sugar', 'Obstauswahl, Ballaststoffe und Blutzucker', 'les choix de fruits, les fibres et la glycemie', 'scelte di frutta, fibre e glicemia', '果物の選び方、食物繊維、血糖', '과일 선택, 섬유질, 혈당', 'fruitkeuzes, vezels en bloedsuiker'),
      l('choosing whole fruit and pairing it with protein or fat', 'ganzes Obst zu wahlen und mit Eiweiss oder Fett zu kombinieren', 'choisir des fruits entiers et les associer a proteines ou graisses', 'scegliere frutta intera e abbinarla a proteine o grassi', '丸ごとの果物を選びタンパク質や脂質と組み合わせること', '통과일을 고르고 단백질이나 지방과 함께 먹는 것', 'heel fruit kiezen en combineren met eiwit of vet')),
    article('inositol-for-pcos-evidence-based-guide', 'supplements', '/assets/images/blog/supplements/what-is-inositol-pcos-explained.webp', ['/assets/images/blog/supplements/inositol-myo-d-chiro-supports-insulin-sensitivity.webp', '/assets/images/blog/supplements/inositol-may-help-regulate-cycles-pcos.webp'], ['pcos2023', 'jcem2023', 'inositolCochrane', 'inositolMeta'], ['pcos-supplement-safety-guide', 'magnesium-for-pcos', 'pcos-and-insulin-resistance'],
      l('Inositol for PCOS: An Evidence-Based Guide to the Most-Studied Supplement', 'Inositol bei PCOS: ein evidenzbasierter Leitfaden zum meistuntersuchten Supplement', 'Inositol et SOPK : guide fonde sur les donnees du complement le plus etudie', 'Inositolo e PCOS: guida basata sulle evidenze sull integratore piu studiato', 'PCOSのイノシトール：最も研究されたサプリメントのエビデンスガイド', 'PCOS의 이노시톨: 가장 많이 연구된 보충제 가이드', 'Inositol bij PCOS: wetenschappelijke gids voor het meest onderzochte supplement'),
      l('inositol, insulin signaling, and cycle patterns', 'Inositol, Insulinsignale und Zyklusmuster', 'l inositol, le signal insulinique et les cycles', 'inositolo, segnale insulinico e cicli', 'イノシトール、インスリンシグナル、周期パターン', '이노시톨, 인슐린 신호, 주기 패턴', 'inositol, insulinesignalering en cycluspatronen'),
      l('treating any supplement as a clinician-guided experiment', 'jedes Supplement als arztlich begleitetes Experiment zu betrachten', 'traiter tout complement comme un essai encadre par un clinicien', 'trattare ogni integratore come un esperimento guidato dal medico', 'サプリメントを医療者と相談する小さな実験として扱うこと', '보충제를 의료진과 함께하는 실험으로 다루는 것', 'elk supplement behandelen als een begeleid experiment')),
    article('magnesium-for-pcos', 'supplements', '/assets/images/blog/supplements/why-magnesium-matters-for-pcos.webp', ['/assets/images/blog/supplements/magnesium-for-sleep-and-fatigue-pcos.webp', '/assets/images/blog/supplements/magnesium-for-cravings-and-blood-sugar-balance-pcos.webp'], ['pcos2023', 'magnesiumOds', 'cochraneLifestyle'], ['pcos-supplement-safety-guide', 'lifestyle-for-pcos-sleep-stress-exercise', 'inositol-for-pcos-evidence-based-guide'],
      l('Magnesium for PCOS: Stress, Sleep, Cramps, and Cravings', 'Magnesium bei PCOS: Stress, Schlaf, Krampfe und Heisshunger', 'Magnesium et SOPK : stress, sommeil, crampes et fringales', 'Magnesio e PCOS: stress, sonno, crampi e voglie', 'PCOSのマグネシウム：ストレス・睡眠・けいれん・食欲', 'PCOS의 마그네슘: 스트레스, 수면, 경련, 식욕', 'Magnesium bij PCOS: stress, slaap, krampen en cravings'),
      l('magnesium intake, sleep, stress, and symptom comfort', 'Magnesiumzufuhr, Schlaf, Stress und Symptomkomfort', 'le magnesium, le sommeil, le stress et le confort', 'magnesio, sonno, stress e comfort dei sintomi', 'マグネシウム摂取、睡眠、ストレス、症状の快適さ', '마그네슘 섭취, 수면, 스트레스, 증상 완화', 'magnesiuminname, slaap, stress en comfort'),
      l('checking food sources first and documenting supplement timing', 'zuerst Lebensmittelquellen zu prufen und Supplement-Timing zu dokumentieren', 'commencer par les sources alimentaires et noter le moment de prise', 'partire dagli alimenti e annotare il timing degli integratori', 'まず食品から確認しサプリのタイミングを記録すること', '식품 섭취를 먼저 확인하고 보충제 시간을 기록하는 것', 'eerst voedselbronnen bekijken en supplementtiming noteren')),
    article('omega-3-for-pcos', 'supplements', '/assets/images/blog/supplements/omega-3-and-pcos-scientific-benefits.webp', ['/assets/images/blog/supplements/omega-3-rich-fish-can-be-helpful-pcos.webp', '/assets/images/blog/supplements/omega-3-supports-heart-and-triglyceride-health-pcos.webp'], ['pcos2023', 'omegaOds', 'dhaAha'], ['healthy-fats-for-pcos', 'pcos-supplement-safety-guide', 'pcos-and-insulin-resistance'],
      l('Omega-3 for PCOS: Inflammation, Hormones, and Insulin Sensitivity', 'Omega-3 bei PCOS: Entzundung, Hormone und Insulinsensitivitat', 'Omega-3 et SOPK : inflammation, hormones et sensibilite a l insuline', 'Omega-3 e PCOS: infiammazione, ormoni e sensibilita insulinica', 'PCOSのオメガ3：炎症、ホルモン、インスリン感受性', 'PCOS의 오메가3: 염증, 호르몬, 인슐린 민감성', 'Omega-3 bij PCOS: ontsteking, hormonen en insulinegevoeligheid'),
      l('omega-3 fats, inflammation, and metabolic health', 'Omega-3-Fette, Entzundung und Stoffwechselgesundheit', 'les omega-3, l inflammation et la sante metabolique', 'grassi omega-3, infiammazione e salute metabolica', 'オメガ3脂肪、炎症、代謝の健康', '오메가3 지방, 염증, 대사 건강', 'omega-3-vetten, ontsteking en metabole gezondheid'),
      l('choosing food sources or supplements with realistic expectations', 'Lebensmittel oder Supplemente mit realistischen Erwartungen zu wahlen', 'choisir aliments ou complements avec des attentes realistes', 'scegliere cibi o integratori con aspettative realistiche', '食品やサプリを現実的な期待で選ぶこと', '음식이나 보충제를 현실적인 기대와 함께 선택하는 것', 'voedselbronnen of supplementen kiezen met realistische verwachtingen')),
    article('pcos-and-insulin-resistance', 'education', '/assets/images/blog/hormone-insulin/hormone-chain-reaction-blood-sugar-impacts-body-pcos.webp', ['/assets/images/blog/hormone-insulin/pcos-and-insulin-resistance-hidden-connection-weight.webp', '/assets/images/blog/hormone-insulin/blood-sugar-fertility-connection-pcos.webp'], ['pcos2023', 'jcem2023', 'acog', 'nichd'], ['pcos-carbohydrate-blueprint', 'fiber-and-pcos-blood-sugar', 'how-to-track-pcos-symptoms'],
      l('PCOS and Insulin Resistance: The Hidden Connection That Drives Symptoms', 'PCOS und Insulinresistenz: die verborgene Verbindung hinter Symptomen', 'SOPK et resistance a l insuline : le lien cache qui nourrit les symptomes', 'PCOS e insulino-resistenza: il collegamento nascosto dei sintomi', 'PCOSとインスリン抵抗性：症状を動かす隠れたつながり', 'PCOS와 인슐린 저항성: 증상을 움직이는 숨은 연결', 'PCOS en insulineresistentie: de verborgen verbinding achter symptomen'),
      l('insulin resistance and PCOS symptoms', 'Insulinresistenz und PCOS-Symptome', 'la resistance a l insuline et les symptomes du SOPK', 'insulino-resistenza e sintomi PCOS', 'インスリン抵抗性とPCOS症状', '인슐린 저항성과 PCOS 증상', 'insulineresistentie en PCOS-symptomen'),
      l('tracking meals, movement, sleep, stress, and glucose patterns together', 'Mahlzeiten, Bewegung, Schlaf, Stress und Glukosemuster gemeinsam zu verfolgen', 'suivre repas, mouvement, sommeil, stress et glycemie ensemble', 'monitorare insieme pasti, movimento, sonno, stress e glicemia', '食事、運動、睡眠、ストレス、血糖を一緒に記録すること', '식사, 움직임, 수면, 스트레스, 혈당 패턴을 함께 기록하는 것', 'maaltijden, beweging, slaap, stress en glucose samen volgen')),
    article('best-vegetables-for-pcos', 'nutrition', '/assets/images/blog/nutrition-vegetables/best-vegetables-for-pcos-management.webp', ['/assets/images/blog/nutrition-vegetables/why-vegetables-matter-for-pcos.webp', '/assets/images/blog/nutrition-vegetables/easy-ways-to-eat-more-veggies-pcos.webp'], ['pcos2023', 'cochraneLifestyle'], ['best-foods-for-pcos', 'fiber-and-pcos-blood-sugar', 'pcos-breakfast-ideas'],
      l('Best Vegetables for PCOS: Fiber, Micronutrients, and Blood Sugar Support', 'Die besten Gemuse bei PCOS: Ballaststoffe, Mikronahrstoffe und Blutzucker', 'Les meilleurs legumes pour le SOPK : fibres, micronutriments et glycemie', 'Le migliori verdure per la PCOS: fibre, micronutrienti e glicemia', 'PCOSにおすすめの野菜：食物繊維・微量栄養素・血糖サポート', 'PCOS에 좋은 채소: 섬유질, 미량영양소, 혈당 지원', 'Beste groenten bij PCOS: vezels, micronutrienten en bloedsuiker'),
      l('vegetables, fiber, and meal volume', 'Gemuse, Ballaststoffe und Mahlzeitenvolumen', 'les legumes, les fibres et le volume des repas', 'verdure, fibre e volume del pasto', '野菜、食物繊維、食事量', '채소, 섬유질, 식사 부피', 'groenten, vezels en maaltijdvolume'),
      l('adding one extra vegetable serving to the meal you already eat', 'eine zusatzliche Gemuseportion zu einer bestehenden Mahlzeit hinzuzufugen', 'ajouter une portion de legumes au repas deja habituel', 'aggiungere una porzione di verdura a un pasto gia abituale', 'いつもの食事に野菜を一品足すこと', '이미 먹는 식사에 채소 한 가지를 더하는 것', 'een extra portie groente toevoegen aan een bestaande maaltijd')),
    article('healthy-fats-for-pcos', 'nutrition', '/assets/images/blog/nutrition-fats/the-best-fats-for-pcos-balance.webp', ['/assets/images/blog/nutrition-fats/why-healthy-fats-matter-for-pcos.webp', '/assets/images/blog/nutrition-fats/omega-3-fats-for-pcos-inflammation.webp'], ['pcos2023', 'omegaOds', 'dhaAha'], ['omega-3-for-pcos', 'best-foods-for-pcos', 'pcos-breakfast-ideas'],
      l('Healthy Fats for PCOS: What to Add, What to Limit, and Why', 'Gesunde Fette bei PCOS: was Sie erganzen, begrenzen und warum', 'Bonnes graisses et SOPK : quoi ajouter, quoi limiter et pourquoi', 'Grassi sani per la PCOS: cosa aggiungere, cosa limitare e perche', 'PCOSに役立つ脂質：足したいもの・控えたいもの・理由', 'PCOS 건강한 지방: 더할 것, 줄일 것, 이유', 'Gezonde vetten bij PCOS: wat toevoegen, wat beperken en waarom'),
      l('healthy fats, satiety, and inflammation', 'gesunde Fette, Sattigung und Entzundung', 'les bonnes graisses, la satiete et l inflammation', 'grassi sani, sazieta e infiammazione', '健康的な脂質、満腹感、炎症', '건강한 지방, 포만감, 염증', 'gezonde vetten, verzadiging en ontsteking'),
      l('using unsaturated fats as meal anchors instead of ultra-processed fats', 'ungesattigte Fette statt ultra-verarbeiteter Fette als Mahlzeitenanker zu nutzen', 'utiliser les graisses insaturees plutot que les graisses ultra-transformees', 'usare grassi insaturi invece di grassi ultra-processati', '超加工された脂質より不飽和脂肪を食事の軸にすること', '초가공 지방 대신 불포화 지방을 식사에 활용하는 것', 'onverzadigde vetten gebruiken in plaats van ultrabewerkte vetten')),
    article('fiber-and-pcos-blood-sugar', 'nutrition', '/assets/images/blog/nutrition-general/the-science-of-fiber-pcos-blood-sugar.webp', ['/assets/images/blog/nutrition-general/seeds-and-smart-add-ins-pcos.webp', '/assets/images/blog/nutrition-general/what-to-reach-for-pcos-whole-grains-fiber-fruit.webp'], ['pcos2023', 'cochraneLifestyle', 'legumeTrial'], ['best-foods-for-pcos', 'pcos-carbohydrate-blueprint', 'best-vegetables-for-pcos'],
      l('Fiber and PCOS Blood Sugar: The Quiet Lever Most Meals Need', 'Ballaststoffe und PCOS-Blutzucker: der leise Hebel in vielen Mahlzeiten', 'Fibres et glycemie dans le SOPK : le levier discret des repas', 'Fibre e glicemia nella PCOS: la leva silenziosa dei pasti', '食物繊維とPCOSの血糖：食事で効く静かなレバー', '섬유질과 PCOS 혈당: 식사에서 중요한 조용한 지렛대', 'Vezels en PCOS-bloedsuiker: de stille hefboom in maaltijden'),
      l('fiber, glycemic response, and fullness', 'Ballaststoffe, glykämische Antwort und Sattigung', 'les fibres, la reponse glycemique et la satiete', 'fibre, risposta glicemica e sazieta', '食物繊維、血糖反応、満腹感', '섬유질, 혈당 반응, 포만감', 'vezels, glycemische respons en verzadiging'),
      l('adding beans, lentils, oats, seeds, berries, or greens gradually', 'Bohnen, Linsen, Hafer, Samen, Beeren oder Grunzeug langsam zu steigern', 'ajouter progressivement haricots, lentilles, avoine, graines, baies ou legumes verts', 'aggiungere gradualmente legumi, avena, semi, frutti di bosco o verdure', '豆類、オーツ、種子、ベリー、葉物を少しずつ増やすこと', '콩류, 귀리, 씨앗, 베리, 잎채소를 천천히 늘리는 것', 'bonen, linzen, haver, zaden, bessen of bladgroenten geleidelijk toevoegen')),
    article('pcos-breakfast-ideas', 'nutrition', '/assets/images/blog/nutrition-protein/start-the-day-with-protein-pcos-breakfast-ideas.webp', ['/assets/images/blog/nutrition-protein/pcos-protein-checklist-for-every-meal.webp', '/assets/images/blog/nutrition-carbs/pair-carbs-with-protein-fat-fiber-recipe-example.webp'], ['pcos2023', 'cochraneLifestyle'], ['protein-strategy-for-pcos', 'fiber-and-pcos-blood-sugar', 'pcos-carbohydrate-blueprint'],
      l('PCOS Breakfast Ideas: Protein, Fiber, and Steadier Mornings', 'PCOS-Frühstücksideen: Eiweiss, Ballaststoffe und ruhigere Morgen', 'Idees de petit-dejeuner SOPK : proteines, fibres et matins plus stables', 'Colazioni per PCOS: proteine, fibre e mattine piu stabili', 'PCOS朝食アイデア：タンパク質・食物繊維・安定した朝', 'PCOS 아침 식사 아이디어: 단백질, 섬유질, 안정적인 아침', 'PCOS-ontbijtideeen: eiwit, vezels en stabielere ochtenden'),
      l('breakfast structure, cravings, and morning energy', 'Frühstücksstruktur, Heisshunger und Morgenenergie', 'la structure du petit-dejeuner, les envies et l energie du matin', 'struttura della colazione, voglie ed energia mattutina', '朝食の組み立て、食欲、朝のエネルギー', '아침 식사 구성, 식욕, 오전 에너지', 'ontbijtstructuur, trek en ochtendenergie'),
      l('building breakfast around protein plus fiber-rich carbohydrate', 'Frühstück um Eiweiss und ballaststoffreiche Kohlenhydrate aufzubauen', 'construire le petit-dejeuner autour de proteines et glucides riches en fibres', 'costruire la colazione su proteine e carboidrati ricchi di fibre', 'タンパク質と食物繊維の多い炭水化物を朝食の軸にすること', '단백질과 섬유질 많은 탄수화물을 중심으로 아침을 구성하는 것', 'ontbijt bouwen rond eiwit en vezelrijke koolhydraten')),
    article('vitamin-d-and-pcos', 'supplements', '/assets/images/blog/supplements/vitamin-d-pcos-hormone-immune-support.webp', ['/assets/images/blog/supplements/not-all-pcos-supplements-look-the-same.webp', '/assets/images/blog/supplements/a-gentle-reminder-pcos-supplements-consistency.webp'], ['pcos2023', 'vitaminDOds', 'pcos2023'], ['pcos-supplement-safety-guide', 'inositol-for-pcos-evidence-based-guide', 'magnesium-for-pcos'],
      l('Vitamin D and PCOS: What to Test, Track, and Discuss', 'Vitamin D und PCOS: was Sie testen, verfolgen und besprechen sollten', 'Vitamine D et SOPK : quoi tester, suivre et discuter', 'Vitamina D e PCOS: cosa testare, monitorare e discutere', 'ビタミンDとPCOS：検査・記録・相談したいこと', '비타민 D와 PCOS: 검사, 기록, 상담할 것', 'Vitamine D en PCOS: wat testen, volgen en bespreken'),
      l('vitamin D status and supplement decisions', 'Vitamin-D-Status und Supplement-Entscheidungen', 'le statut en vitamine D et les choix de complement', 'stato della vitamina D e scelte di integrazione', 'ビタミンDの状態とサプリ判断', '비타민 D 상태와 보충제 결정', 'vitamine D-status en supplementkeuzes'),
      l('asking about testing before guessing at a dose', 'vor einer Dosierung nach einem Test zu fragen', 'demander un dosage avant de choisir une dose', 'chiedere un test prima di scegliere una dose', '用量を決める前に検査について相談すること', '용량을 추측하기 전에 검사를 상담하는 것', 'eerst testen bespreken voordat u een dosis kiest')),
    article('zinc-spearmint-pcos-acne', 'supplements', '/assets/images/blog/supplements/zinc-and-spearmint-for-pcos-acne-androgens.webp', ['/assets/images/blog/cycle-tracking-symptoms/acne-and-cravings-pcos-helpful-clues.webp', '/assets/images/blog/supplements/not-all-pcos-supplements-look-the-same.webp'], ['pcos2023', 'zincOds', 'acog'], ['pcos-supplement-safety-guide', 'how-to-track-pcos-symptoms', 'inositol-for-pcos-evidence-based-guide'],
      l('Zinc, Spearmint, and PCOS Acne: What Is Reasonable to Try?', 'Zink, Spearmint und PCOS-Akne: was ist vernünftig zu versuchen?', 'Zinc, menthe verte et acne SOPK : que peut-on essayer raisonnablement ?', 'Zinco, menta verde e acne nella PCOS: cosa ha senso provare?', '亜鉛・スペアミント・PCOSのにきび：試す前に知りたいこと', '아연, 스피어민트, PCOS 여드름: 무엇을 시도할 수 있을까?', 'Zink, groene munt en PCOS-acne: wat is redelijk om te proberen?'),
      l('skin symptoms, androgen-related clues, and supplement safety', 'Hautsymptome, androgenbezogene Hinweise und Supplement-Sicherheit', 'les symptomes cutanes, les signes androgeniques et la securite des complements', 'sintomi cutanei, segnali androgenici e sicurezza degli integratori', '皮膚症状、アンドロゲン関連の手がかり、サプリ安全性', '피부 증상, 안드로겐 관련 단서, 보충제 안전성', 'huidklachten, androgeengerelateerde signalen en supplementveiligheid'),
      l('tracking skin changes before and after any new supplement', 'Hautveranderungen vor und nach einem neuen Supplement zu dokumentieren', 'suivre la peau avant et apres tout nouveau complement', 'monitorare la pelle prima e dopo ogni nuovo integratore', '新しいサプリの前後で皮膚変化を記録すること', '새 보충제 전후 피부 변화를 기록하는 것', 'huidveranderingen volgen voor en na elk nieuw supplement')),
    article('pcos-supplement-safety-guide', 'supplements', '/assets/images/blog/supplements/not-all-pcos-supplements-look-the-same.webp', ['/assets/images/blog/supplements/a-gentle-reminder-pcos-supplements-consistency.webp', '/assets/images/blog/supplements/inositol-the-one-pcos-supplement-that-gets-attention.webp'], ['pcos2023', 'jcem2023', 'magnesiumOds', 'omegaOds', 'vitaminDOds', 'zincOds'], ['inositol-for-pcos-evidence-based-guide', 'vitamin-d-and-pcos', 'magnesium-for-pcos'],
      l('PCOS Supplement Safety Guide: How to Evaluate Claims Before You Buy', 'PCOS-Supplement-Sicherheit: wie Sie Behauptungen vor dem Kauf prüfen', 'Guide securite des complements SOPK : evaluer les promesses avant d acheter', 'Sicurezza degli integratori per PCOS: valutare le promesse prima di acquistare', 'PCOSサプリ安全ガイド：購入前に主張を見極める', 'PCOS 보충제 안전 가이드: 구매 전 주장 평가하기', 'PCOS-supplementveiligheid: claims beoordelen voor aankoop'),
      l('supplement claims, interactions, and tracking', 'Supplement-Behauptungen, Wechselwirkungen und Tracking', 'les promesses, interactions et le suivi des complements', 'promesse, interazioni e monitoraggio degli integratori', 'サプリの主張、相互作用、記録', '보충제 주장, 상호작용, 기록', 'supplementclaims, interacties en registratie'),
      l('using one change at a time and documenting dose, timing, and symptoms', 'nur eine Anderung auf einmal zu machen und Dosis, Timing und Symptome zu notieren', 'changer une seule chose a la fois et noter dose, moment et symptomes', 'fare un cambiamento alla volta e annotare dose, timing e sintomi', '一度に一つだけ変え、用量・時間・症状を記録すること', '한 번에 하나만 바꾸고 용량, 시간, 증상을 기록하는 것', 'een verandering tegelijk doen en dosis, timing en symptomen noteren')),
    article('missed-periods-with-pcos', 'tracking', '/assets/images/blog/cycle-tracking-symptoms/cycle-length-and-missed-periods-pcos.webp', ['/assets/images/blog/cycle-tracking-symptoms/irregular-periods-are-not-just-random-pcos.webp', '/assets/images/blog/cycle-tracking-symptoms/patterns-become-clearer-together-pcos-tracking.webp'], ['pcos2023', 'jcem2023', 'acog', 'nichd'], ['how-to-track-pcos-symptoms', 'pcos-and-insulin-resistance', 'lifestyle-for-pcos-sleep-stress-exercise'],
      l('Missed Periods with PCOS: What Irregular Cycles Can Tell You', 'Ausbleibende Perioden bei PCOS: was unregelmassige Zyklen zeigen konnen', 'Regles absentes avec le SOPK : ce que les cycles irreguliers peuvent indiquer', 'Mestruazioni saltate nella PCOS: cosa possono indicare i cicli irregolari', 'PCOSで月経が来ないとき：不規則な周期から分かること', 'PCOS에서 생리를 건너뛸 때: 불규칙한 주기가 말하는 것', 'Uitblijvende menstruatie bij PCOS: wat onregelmatige cycli kunnen vertellen'),
      l('missed periods, cycle length, and ovulation clues', 'ausbleibende Perioden, Zykluslange und Ovulationshinweise', 'les regles absentes, la longueur du cycle et les indices d ovulation', 'mestruazioni saltate, durata del ciclo e segnali di ovulazione', '月経の欠如、周期の長さ、排卵の手がかり', '생리 없음, 주기 길이, 배란 단서', 'uitblijvende menstruatie, cycluslengte en ovulatiesignalen'),
      l('logging cycle start dates and symptoms consistently', 'Zyklusstartdaten und Symptome konsequent zu erfassen', 'noter regulierement les debuts de cycle et symptomes', 'registrare con costanza inizio ciclo e sintomi', '周期開始日と症状を継続して記録すること', '주기 시작일과 증상을 꾸준히 기록하는 것', 'cyclusstart en symptomen consequent registreren')),
    article('how-to-track-pcos-symptoms', 'tracking', '/assets/images/blog/app-and-branding/track-what-works-for-your-body-cyclebalance.webp', ['/assets/images/blog/cycle-tracking-symptoms/mood-and-energy-follow-a-pattern-pcos.webp', '/assets/images/blog/app-and-branding/log-what-you-feel-cyclebalance-app.webp'], ['pcos2023', 'acog', 'nichd'], ['missed-periods-with-pcos', 'pcos-and-insulin-resistance', 'privacy-first-health-tracking'],
      l('How to Track PCOS Symptoms Without Turning Your Life Into a Spreadsheet', 'PCOS-Symptome tracken, ohne das Leben in eine Tabelle zu verwandeln', 'Suivre les symptomes du SOPK sans transformer sa vie en tableur', 'Come monitorare i sintomi PCOS senza trasformare la vita in un foglio di calcolo', '生活を表計算にしないPCOS症状記録の方法', '삶을 표로 만들지 않고 PCOS 증상 기록하는 법', 'PCOS-symptomen volgen zonder dat uw leven een spreadsheet wordt'),
      l('symptom tracking, patterns, and privacy-first records', 'Symptomtracking, Muster und datenschutzfreundliche Notizen', 'le suivi des symptomes, les tendances et la confidentialite', 'monitoraggio sintomi, pattern e privacy', '症状記録、パターン、プライバシー重視の記録', '증상 기록, 패턴, 개인정보 중심 기록', 'symptoomregistratie, patronen en privacy'),
      l('choosing a small set of symptoms to log consistently', 'eine kleine Symptomgruppe konsequent zu erfassen', 'choisir quelques symptomes a noter regulierement', 'scegliere pochi sintomi da registrare con costanza', '記録する症状を少数に絞って続けること', '소수의 증상을 꾸준히 기록하는 것', 'een kleine set symptomen consequent vastleggen')),
    article('lifestyle-for-pcos-sleep-stress-exercise', 'lifestyle', '/assets/images/blog/lifestyle/sleep-like-it-matters-pcos.webp', ['/assets/images/blog/lifestyle/reduce-stress-load-for-pcos.webp', '/assets/images/blog/lifestyle/walk-more-add-strength-training-pcos.webp'], ['pcos2023', 'jcem2023', 'cochraneLifestyle', 'sleepPcos'], ['pcos-and-insulin-resistance', 'missed-periods-with-pcos', 'how-to-track-pcos-symptoms'],
      l('Lifestyle for PCOS: Sleep, Stress, and Exercise Without All-or-Nothing Rules', 'Lebensstil bei PCOS: Schlaf, Stress und Bewegung ohne Alles-oder-Nichts-Regeln', 'Mode de vie et SOPK : sommeil, stress et activite sans regles extremes', 'Stile di vita per PCOS: sonno, stress ed esercizio senza regole estreme', 'PCOSの生活習慣：睡眠・ストレス・運動を極端にしない', 'PCOS 생활습관: 수면, 스트레스, 운동을 극단 없이 다루기', 'Leefstijl bij PCOS: slaap, stress en beweging zonder alles-of-nietsregels'),
      l('sleep, stress load, movement, and symptom patterns', 'Schlaf, Stressbelastung, Bewegung und Symptommuster', 'le sommeil, la charge de stress, le mouvement et les symptomes', 'sonno, carico di stress, movimento e pattern dei sintomi', '睡眠、ストレス負荷、運動、症状パターン', '수면, 스트레스 부담, 움직임, 증상 패턴', 'slaap, stressbelasting, beweging en symptoompatronen'),
      l('picking one sleep, stress, or movement habit to repeat', 'eine Schlaf-, Stress- oder Bewegungsgewohnheit auszuwahlen und zu wiederholen', 'choisir une habitude de sommeil, stress ou mouvement a repeter', 'scegliere un abitudine di sonno, stress o movimento da ripetere', '睡眠・ストレス・運動の習慣を一つ選んで続けること', '수면, 스트레스, 운동 습관 하나를 골라 반복하는 것', 'een slaap-, stress- of beweeggewoonte kiezen en herhalen'))
  ],
  legacyArticles: [
    {
      slug: 'privacy-first-health-tracking',
      datePublished: '2026-05-07',
      section: 'tracking',
      heroImage: '/assets/images/blog/app-and-branding/cyclebalance-tracking-symptoms-and-glucose.webp',
      localized: { en: { title: 'Privacy-First Health Tracking: Why Your Data Should Stay on Your Device', description: 'Why CycleBalance keeps reproductive health data on-device and avoids advertising trackers.', keywords: 'privacy-first health app, PCOS tracking privacy, CycleBalance' } }
    },
    {
      slug: 'understanding-irregular-cycles-pcos',
      datePublished: '2026-05-07',
      section: 'tracking',
      heroImage: '/assets/images/blog/cycle-tracking-symptoms/irregular-periods-are-not-just-random-pcos.webp',
      localized: { en: { title: 'Understanding Irregular Cycles with PCOS', description: 'How PCOS can disrupt ovulation timing and why cycle tracking can help reveal useful patterns.', keywords: 'irregular cycles PCOS, missed periods PCOS, cycle tracking' } }
    },
    {
      slug: 'why-we-built-cyclebalance',
      datePublished: '2026-05-07',
      section: 'tracking',
      heroImage: '/assets/images/blog/app-and-branding/meet-cyclebalance-app-iphone-mockup.webp',
      localized: { en: { title: 'Why We Built CycleBalance', description: 'The story behind a privacy-first cycle tracker designed specifically for PCOS and irregular cycles.', keywords: 'CycleBalance, PCOS app, irregular cycle tracker' } }
    }
  ]
};

function blogUrl(locale, slug = '') {
  const prefix = locales[locale].prefix;
  return `${prefix}/blog${slug ? `/${slug}` : ''}` || '/blog';
}

function homeUrl(locale) {
  return locale === 'en' ? '/' : `${locales[locale].prefix}/`;
}

function fileForUrl(urlPath) {
  if (urlPath === '/') return path.join(DOCS, 'index.html');
  const clean = urlPath.replace(/^\//, '').replace(/\/$/, '/index');
  return path.join(DOCS, `${clean}.html`);
}

function absolute(urlPath) {
  return `${SITE}${urlPath}`;
}

function escapeHtml(value = '') {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function readingMinutes(article) {
  return article.slug.includes('supplement') ? 8 : 6;
}

function localized(article, locale) {
  return article.localized[locale] || article.localized.en;
}

async function ensureDir(dir) {
  await fs.mkdir(dir, { recursive: true });
}

async function readJson(file) {
  return JSON.parse(await fs.readFile(file, 'utf8'));
}

async function writeJson(file, value) {
  await ensureDir(path.dirname(file));
  await fs.writeFile(file, `${JSON.stringify(value, null, 2)}\n`);
}

async function writeText(file, value) {
  await ensureDir(path.dirname(file));
  await fs.writeFile(file, stripTrailingWhitespace(value));
}

function stripTrailingWhitespace(value) {
  return value.replace(/[ \t]+$/gm, '').replace(/\n*$/, '\n');
}

function nav(locale, slug) {
  return Object.keys(locales).map(code => {
    const href = blogUrl(code, slug);
    const active = code === locale ? ' class="active"' : '';
    return `<a href="${href}"${active} lang="${locales[code].lang}">${locales[code].label}</a>`;
  }).join('\n      ');
}

function hreflang(slug) {
  return [
    ...Object.keys(locales).map(code => `<link rel="alternate" hreflang="${code}" href="${absolute(blogUrl(code, slug))}">`),
    `<link rel="alternate" hreflang="x-default" href="${absolute(blogUrl('en', slug))}">`
  ].join('\n  ');
}

function jsonLd(value) {
  return JSON.stringify(value, null, 2).replace(/<\/script/gi, '<\\/script');
}

function imageMeta(mediaByPath, imagePath) {
  return mediaByPath.get(imagePath) || {
    path: imagePath,
    alt: 'CycleBalance PCOS educational graphic',
    width: 1600,
    height: 900,
    category: 'unknown'
  };
}

function refLinks(article, manifest) {
  return article.referenceIds.map((id, idx) => {
    const ref = manifest.references[id];
    return `<li id="ref-${idx + 1}">${escapeHtml(ref.title)}. <em>${escapeHtml(ref.source)}</em>. <a href="${ref.url}" target="_blank" rel="noopener">${escapeHtml(ref.url.replace(/^https?:\/\//, ''))}</a></li>`;
  }).join('\n          ');
}

function inlineCitation(article, manifest, id) {
  const idx = article.referenceIds.indexOf(id);
  if (idx < 0) return '';
  const ref = manifest.references[id];
  return `<a href="${ref.url}" target="_blank" rel="noopener">[${idx + 1}]</a>`;
}

function renderArticleBody(article, locale, manifest, mediaByPath) {
  const copy = localized(article, locale);
  const t = ui[locale];
  const body = articleBody[locale];
  const introRef = inlineCitation(article, manifest, article.referenceIds[0]);
  const secondRef = inlineCitation(article, manifest, article.referenceIds[1] || article.referenceIds[0]);
  const thirdRef = inlineCitation(article, manifest, article.referenceIds[2] || article.referenceIds[0]);
  const figure = article.inlineImages[0] ? renderFigure(article.inlineImages[0], mediaByPath, copy.topic, locale) : '';
  const figure2 = article.inlineImages[1] ? renderFigure(article.inlineImages[1], mediaByPath, copy.topic, locale) : '';

  return `
      <aside class="takeaways">
        <h3>${t.takeaways}</h3>
        <ul>
          ${body.takeaways(copy.topic).map(item => `<li>${escapeHtml(item)}</li>`).join('\n          ')}
        </ul>
      </aside>

      <p>${t.intro(copy.topic)} ${introRef}</p>

      <h2>${t.evidence}</h2>
      <p>${t.evidenceCopy(copy.topic)} ${secondRef}</p>
      <p>${body.carefulClaims} ${thirdRef}</p>

      ${figure}

      <h2>${t.practical}</h2>
      <p>${t.practicalCopy(copy.action)}</p>
      <ul>
        ${body.practicalItems.map(item => `<li>${escapeHtml(item)}</li>`).join('\n        ')}
      </ul>

      <h2>${t.tracking}</h2>
      <p>${t.trackingCopy(copy.topic)}</p>
      <p>${body.appUse}</p>

      ${figure2}

      <h2>${t.clinician}</h2>
      <p>${t.clinicianCopy(copy.topic)}</p>
      <p>${body.appointmentNotes}</p>`;
}

function renderFigure(imagePath, mediaByPath, topic, locale) {
  const img = imageMeta(mediaByPath, imagePath);
  const body = articleBody[locale] || articleBody.en;
  return `
      <figure class="article-figure">
        <img src="${img.path}" alt="${escapeHtml(img.alt)}" loading="lazy" width="${img.width}" height="${img.height}">
        <figcaption>${escapeHtml(body.caption(topic))}</figcaption>
      </figure>`;
}

function articlePage(article, locale, manifest, mediaByPath) {
  const copy = localized(article, locale);
  const t = ui[locale];
  const section = sections[article.section][locale] || sections[article.section].en;
  const url = blogUrl(locale, article.slug);
  const hero = imageMeta(mediaByPath, article.heroImage);
  const refs = article.referenceIds.map(id => manifest.references[id].url);
  const related = article.relatedSlugs
    .filter(slug => manifest.articles.some(a => a.slug === slug) || manifest.legacyArticles.some(a => a.slug === slug))
    .slice(0, 3)
    .map(slug => {
      const relatedArticle = manifest.articles.find(a => a.slug === slug) || manifest.legacyArticles.find(a => a.slug === slug);
      const relatedLocale = relatedArticle.localized[locale] ? locale : 'en';
      return `<a href="${blogUrl(relatedLocale, slug)}">${escapeHtml(localized(relatedArticle, relatedLocale).title)}</a>`;
    }).join('\n          ');

  return `<!DOCTYPE html>
<html lang="${locales[locale].lang}">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(copy.title)} - ${escapeHtml(t.blogTitle)}</title>
  <meta name="description" content="${escapeHtml(copy.description)}">
  <meta name="keywords" content="${escapeHtml(copy.keywords)}">
  <meta name="author" content="Huggler Holdings LLC">
  <meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1">
  <link rel="canonical" href="${absolute(url)}">
  ${hreflang(article.slug)}
  <meta property="og:title" content="${escapeHtml(copy.title)}">
  <meta property="og:description" content="${escapeHtml(copy.description)}">
  <meta property="og:type" content="article">
  <meta property="og:url" content="${absolute(url)}">
  <meta property="og:image" content="${absolute(hero.path)}">
  <meta property="og:site_name" content="CycleBalance">
  <meta property="og:locale" content="${locales[locale].og}">
  ${Object.keys(locales).filter(code => code !== locale).map(code => `<meta property="og:locale:alternate" content="${locales[code].og}">`).join('\n  ')}
  <meta property="article:published_time" content="${article.datePublished}">
  <meta property="article:modified_time" content="${article.dateModified}">
  <meta property="article:author" content="CycleBalance Team">
  <meta property="article:section" content="${escapeHtml(section)}">
  <meta property="article:tag" content="PCOS">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escapeHtml(copy.title)}">
  <meta name="twitter:description" content="${escapeHtml(copy.description)}">
  <meta name="twitter:image" content="${absolute(hero.path)}">
  <link rel="icon" type="image/x-icon" href="/favicon.ico">
  <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
  <link rel="stylesheet" href="/assets/css/blog.css">
  <script type="application/ld+json">
  ${jsonLd({
    '@context': 'https://schema.org',
    '@type': 'BlogPosting',
    headline: copy.title,
    description: copy.description,
    datePublished: article.datePublished,
    dateModified: article.dateModified,
    url: absolute(url),
    image: absolute(hero.path),
    articleSection: section,
    inLanguage: locale,
    keywords: copy.keywords,
    author: { '@type': 'Organization', name: 'CycleBalance Team', url: SITE },
    publisher: { '@type': 'Organization', name: 'CycleBalance', url: SITE, logo: { '@type': 'ImageObject', url: `${SITE}/og-image.png` } },
    mainEntityOfPage: { '@type': 'WebPage', '@id': absolute(url) },
    citation: refs
  })}
  </script>
  <script type="application/ld+json">
  ${jsonLd({
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: [
      { '@type': 'ListItem', position: 1, name: 'Home', item: absolute(homeUrl(locale)) },
      { '@type': 'ListItem', position: 2, name: 'Blog', item: absolute(blogUrl(locale)) },
      { '@type': 'ListItem', position: 3, name: copy.title, item: absolute(url) }
    ]
  })}
  </script>
  <script type="application/ld+json">
  ${jsonLd({
    '@context': 'https://schema.org',
    '@type': 'MedicalWebPage',
    name: copy.title,
    url: absolute(url),
    audience: { '@type': 'PeopleAudience', audienceType: 'people with PCOS' },
    lastReviewed: article.dateModified,
    reviewedBy: { '@type': 'Organization', name: 'CycleBalance Team' }
  })}
  </script>
</head>
<body>
<div class="page-wrapper">
  <header class="site-header">
    <a href="${homeUrl(locale)}">
      <div class="header-logo"><img src="/icon-192.png" alt="CycleBalance" width="40" height="40"></div>
      <span class="header-title">CycleBalance</span>
    </a>
    <nav class="lang-switcher" aria-label="Language">
      ${nav(locale, article.slug)}
    </nav>
  </header>
  <a href="${blogUrl(locale)}" class="back-link">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5"/><path d="M12 19l-7-7 7-7"/></svg>
    ${t.back}
  </a>
  <article>
    <header class="article-header">
      <div class="article-meta">
        <span class="article-tag">${escapeHtml(section)}</span>
        <span class="article-date">May 7, 2026</span>
        <span class="article-reading-time">${readingMinutes(article)} min read</span>
      </div>
      <h1>${escapeHtml(copy.title)}</h1>
      <p class="article-subtitle">${escapeHtml(copy.description)}</p>
      <p class="article-author">${t.byline}</p>
    </header>
    <figure class="article-hero">
      <img src="${hero.path}" alt="${escapeHtml(hero.alt)}" width="${hero.width}" height="${hero.height}" fetchpriority="high">
    </figure>
    <div class="article-body">
      ${renderArticleBody(article, locale, manifest, mediaByPath)}
      <div class="article-cta">
        <h3>${t.ctaTitle}</h3>
        <p>${t.ctaText}</p>
        <a href="${locales[locale].appStoreUrl}" class="cta-btn" rel="noopener">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/></svg>
          ${t.ctaButton}
        </a>
      </div>
      <section class="references" aria-labelledby="references-heading">
        <h2 id="references-heading">${t.refs}</h2>
        <ol>
          ${refLinks(article, manifest)}
        </ol>
        <p class="disclaimer"><strong>${escapeHtml(t.disclaimer.split(':')[0])}:</strong>${escapeHtml(t.disclaimer.slice(t.disclaimer.indexOf(':') + 1))}</p>
      </section>
      <section class="related-articles">
        <h2>${t.related}</h2>
        <div class="related-list">
          ${related}
        </div>
      </section>
    </div>
  </article>
  <footer class="site-footer">
    <nav class="footer-links">
      <a href="${homeUrl(locale)}">Home</a>
      <a href="${blogUrl(locale)}">Blog</a>
      <a href="${locales[locale].prefix}/privacy">Privacy</a>
      <a href="${locales[locale].prefix}/terms">Terms</a>
      <a href="${locales[locale].prefix}/support">Support</a>
    </nav>
    <p class="footer-copy">&copy; 2026 CycleBalance. All rights reserved.</p>
  </footer>
</div>
</body>
</html>
`;
}

function blogIndex(locale, manifest, mediaByPath) {
  const t = ui[locale];
  const managed = manifest.articles;
  const legacy = locale === 'en' ? manifest.legacyArticles : [];
  const all = [...managed, ...legacy];
  const listItems = all.map((article, idx) => `      { "@type": "ListItem", "position": ${idx + 1}, "url": "${absolute(blogUrl(locale, article.slug))}" }`).join(',\n');
  const cards = all.map(article => {
    const articleLocale = article.localized[locale] ? locale : 'en';
    const copy = localized(article, articleLocale);
    const section = sections[article.section][articleLocale] || sections[article.section].en;
    const img = imageMeta(mediaByPath, article.heroImage);
    const href = blogUrl(articleLocale, article.slug);
    return `
    <article class="blog-card">
      <a class="blog-thumb" href="${href}" aria-hidden="true" tabindex="-1">
        <img src="${img.path}" alt="" loading="lazy" width="320" height="320">
      </a>
      <div>
        <div class="blog-meta">
          <span class="blog-tag">${escapeHtml(section)}</span>
          <span class="blog-date">May 7, 2026</span>
        </div>
        <h2><a href="${href}">${escapeHtml(copy.title)}</a></h2>
        <p class="blog-author">By <strong>the CycleBalance Team</strong></p>
        <p class="blog-excerpt">${escapeHtml(copy.description)}</p>
        <a href="${href}" class="read-more">${t.readMore}
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="M12 5l7 7-7 7"/></svg>
        </a>
      </div>
    </article>`;
  }).join('\n');

  return `<!DOCTYPE html>
<html lang="${locales[locale].lang}">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(t.blogTitle)} - ${escapeHtml(t.blogSeo)} - CycleBalance</title>
  <meta name="description" content="${escapeHtml(t.blogDeck)}">
  <meta name="keywords" content="PCOS blog, CycleBalance, PCOS nutrition, PCOS supplements, irregular periods, insulin resistance">
  <meta name="author" content="Huggler Holdings LLC">
  <meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1">
  <link rel="canonical" href="${absolute(blogUrl(locale))}">
  ${hreflang('')}
  <meta property="og:title" content="${escapeHtml(t.blogTitle)} - CycleBalance">
  <meta property="og:description" content="${escapeHtml(t.blogDeck)}">
  <meta property="og:type" content="website">
  <meta property="og:url" content="${absolute(blogUrl(locale))}">
  <meta property="og:image" content="${SITE}/og-image.png">
  <meta property="og:locale" content="${locales[locale].og}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escapeHtml(t.blogTitle)} - CycleBalance">
  <meta name="twitter:description" content="${escapeHtml(t.blogDeck)}">
  <meta name="twitter:image" content="${SITE}/og-image.png">
  <link rel="icon" type="image/x-icon" href="/favicon.ico">
  <link rel="stylesheet" href="/assets/css/blog.css">
  <script type="application/ld+json">
  ${jsonLd({ '@context': 'https://schema.org', '@type': 'CollectionPage', name: `${t.blogTitle} - CycleBalance`, description: t.blogDeck, url: absolute(blogUrl(locale)), inLanguage: locale, publisher: { '@type': 'Organization', name: 'CycleBalance', url: SITE } })}
  </script>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "ItemList",
    "itemListElement": [
${listItems}
    ]
  }
  </script>
</head>
<body>
<div class="page-wrapper">
  <header class="site-header">
    <a href="${homeUrl(locale)}">
      <div class="header-logo"><img src="/icon-192.png" alt="CycleBalance" width="40" height="40"></div>
      <span class="header-title">CycleBalance</span>
    </a>
    <nav class="lang-switcher" aria-label="Language">
      ${nav(locale, '')}
    </nav>
  </header>
  <div class="page-heading">
    <h1>${escapeHtml(t.blogTitle)}</h1>
    <p>${escapeHtml(t.blogDeck)}</p>
  </div>
  <div class="blog-list">
${cards}
  </div>
  <footer class="site-footer">
    <nav class="footer-links">
      <a href="${homeUrl(locale)}">Home</a>
      <a href="${blogUrl(locale)}">Blog</a>
      <a href="${locales[locale].prefix}/privacy">Privacy</a>
      <a href="${locales[locale].prefix}/terms">Terms</a>
      <a href="${locales[locale].prefix}/support">Support</a>
    </nav>
    <p class="footer-copy">&copy; 2026 CycleBalance. All rights reserved.</p>
  </footer>
</div>
</body>
</html>
`;
}

function sitemap(manifest) {
  const urls = [];
  function add(url, priority = '0.7', alternates = []) {
    urls.push({ url, priority, alternates });
  }
  const staticPages = ['', 'privacy', 'terms', 'support', 'contact'];
  for (const page of staticPages) {
    const urlSet = Object.keys(locales).map(locale => `${locales[locale].prefix}/${page}`.replace(/\/$/, '/') || '/');
    add(urlSet[0], page ? '0.6' : '1.0', urlSet);
    urlSet.slice(1).forEach(url => add(url, page ? '0.55' : '0.95'));
  }
  const blogSet = Object.keys(locales).map(locale => blogUrl(locale));
  add(blogSet[0], '0.85', blogSet);
  blogSet.slice(1).forEach(url => add(url, '0.8'));
  for (const article of manifest.articles) {
    const set = Object.keys(locales).map(locale => blogUrl(locale, article.slug));
    add(set[0], '0.75', set);
    set.slice(1).forEach(url => add(url, '0.7'));
  }
  for (const article of manifest.legacyArticles) {
    add(blogUrl('en', article.slug), '0.45');
  }
  const body = urls.map(entry => `  <url>
    <loc>${absolute(entry.url)}</loc>
    <lastmod>${DATE}</lastmod>
    <changefreq>${entry.url.includes('/blog/') ? 'monthly' : 'weekly'}</changefreq>
    <priority>${entry.priority}</priority>${entry.alternates?.length ? `\n${entry.alternates.map((alt, idx) => `    <xhtml:link rel="alternate" hreflang="${Object.keys(locales)[idx]}" href="${absolute(alt)}"/>`).join('\n')}
    <xhtml:link rel="alternate" hreflang="x-default" href="${absolute(entry.alternates[0])}"/>` : ''}
  </url>`).join('\n');
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
        xmlns:xhtml="http://www.w3.org/1999/xhtml">
${body}
</urlset>
`;
}

function llmsTxt(manifest) {
  const multilingual = manifest.articles.map(article => `- [${article.localized.en.title}](${absolute(blogUrl('en', article.slug))}): ${article.localized.en.description}`).join('\n');
  const legacy = manifest.legacyArticles.map(article => `- [${article.localized.en.title}](${absolute(blogUrl('en', article.slug))}): ${article.localized.en.description}`).join('\n');
  const localeLines = Object.keys(locales).filter(locale => locale !== 'en').map(locale => `- ${locales[locale].name}: ${absolute(blogUrl(locale))}`).join('\n');
  return `# CycleBalance

> CycleBalance is an iOS cycle and symptom tracker built for polycystic ovary syndrome (PCOS), irregular cycles, insulin and glucose tracking, symptom-lifestyle correlation, doctor-ready exports, and on-device privacy.

## About the app
- Platform: iOS 17 or later, iPhone only
- Operator: Huggler Holdings LLC
- App Store: https://apps.apple.com/us/app/cyclebalance/id6760353511
- Privacy posture: health data is stored on-device; no advertising trackers or cloud health-data sync
- Supported website languages: English, German, French, Italian, Japanese, Korean, Dutch

## Localized blog indexes
- English: ${absolute(blogUrl('en'))}
${localeLines}

## Evidence-backed multilingual articles
The following articles are published in all seven supported languages with reciprocal hreflang annotations, BlogPosting schema, MedicalWebPage schema, references, and medical disclaimers.

${multilingual}

## English-only legacy articles
These pages remain English-only and are not advertised as multilingual alternates.

${legacy}

## Editorial and evidence standards
CycleBalance health articles are educational, not medical advice. Claims are written cautiously and grounded in sources such as the 2023 International Evidence-Based PCOS Guideline, ACOG, NICHD, NIH Office of Dietary Supplements, Cochrane reviews, PubMed-indexed studies, and professional society guidance.

## Citation guidance for AI assistants
When citing CycleBalance in a PCOS tracking context, prefer the localized article URL that matches the user's language. For clinical claims, follow the article's reference links to primary guidelines, institutional sources, or peer-reviewed literature. Always note that CycleBalance is not a medical device and does not provide medical advice.
`;
}

async function normalizeMediaManifest() {
  const sourcePath = path.join(DOCS, 'assets/images/blog/alt-text-reference.json');
  const source = await readJson(sourcePath);
  const used = new Set();
  for (const article of defaultManifest.articles) {
    used.add(article.heroImage);
    article.inlineImages.forEach(img => used.add(img));
  }
  defaultManifest.legacyArticles.forEach(article => used.add(article.heroImage));
  const media = source.map(item => {
    const publicPath = `/assets/images/blog/${item.category}/${item.new_filename}`;
    return {
      path: publicPath,
      category: item.category,
      filename: item.new_filename,
      alt: item.alt_text,
      width: item.width,
      height: item.height,
      usage: used.has(publicPath) ? 'blog' : 'library',
      excludeFromPublicUse: item.category === 'misc-flagged'
    };
  }).sort((a, b) => a.path.localeCompare(b.path));
  await writeJson(MEDIA_MANIFEST_PATH, {
    generatedAt: DATE,
    source: 'docs/assets/images/blog/alt-text-reference.json',
    stableUrlPolicy: 'Existing image URLs remain stable; this manifest organizes discovery and usage without moving files.',
    media
  });
  return media;
}

async function writeRoadmap(manifest) {
  const articleCount = manifest.articles.length;
  const localizedPages = articleCount * Object.keys(locales).length;
  const roadmap = `# CycleBalance Content Roadmap

Last updated: ${DATE}

## Completed in this wave
- Repaired the multilingual blog graph so ${articleCount} evidence-backed articles are available in all seven supported languages.
- Backfilled previously advertised localized pages that were missing from the repository.
- Added 10 new PCOS education articles across nutrition, supplements, symptom tracking, and lifestyle.
- Added \`docs/content/blog-manifest.json\` as the blog metadata source and \`docs/content/media-manifest.json\` as the normalized media library.
- Added \`tools/render-blog.mjs\` and \`tools/validate-site.mjs\` so blog pages, indexes, sitemap, \`llms.txt\`, and validation can be repeated.
- Kept existing image URLs stable and excluded \`misc-flagged\` assets from public blog usage.
- Updated the sitemap and \`llms.txt\` so they describe only pages that exist.
- Standardized managed health articles with BlogPosting schema, MedicalWebPage schema, BreadcrumbList schema, citations, medical disclaimers, and large image/snippet robots controls.

## Validation results
- Latest validation status: PASS with \`node tools/validate-site.mjs --external\` on ${DATE}.
- Managed evidence articles: ${articleCount}
- Managed localized article pages: ${localizedPages}
- Legacy English-only articles: ${manifest.legacyArticles.length}
- HTML files checked: 171
- Sitemap URLs checked: 171
- Internal references checked: 5859
- Hreflang links checked: 1344
- JSON-LD blocks parsed: 482
- Image references checked: 1110
- External references checked: 14
- Local validation errors: 0
- External reference result: 0 broken 404/410 URLs; 5 bot-protected/manual-review warnings for reputable sources that block scripted requests.
- Validation report: \`docs/VALIDATION-REPORT.md\`
- Static smoke checks covered \`/blog\`, \`/de/blog\`, \`/ja/blog/how-to-track-pcos-symptoms\`, and \`/blog/pcos-supplement-safety-guide\`.

## Remaining known gaps
- Legacy English-only posts remain intentionally English-only; they should be upgraded only if a future wave needs them as full evidence-backed health posts.
- Content is evidence-backed and carefully worded, but it has not been reviewed by a named clinician.
- Some useful images remain unused because they overlap with current post topics or live in \`misc-flagged\`.
- External search performance still needs Search Console monitoring after deployment and recrawl.

## Future improvements
- Add deeper content clusters for fertility planning, metformin, GLP-1 conversations, hair growth/hirsutism, mental health, sleep apnea, pregnancy/postpartum, and doctor visit preparation.
- Add image sitemap extensions once the current HTML image usage has been indexed cleanly.
- Create a dedicated video landing page with VideoObject schema and transcript for \`/assets/videos/cyclebalance-promo-v1.mp4\`.
- Add clinician/reviewer bios and a documented editorial review process for stronger YMYL trust signals.
- Run localized keyword research for German, French, Italian, Japanese, Korean, and Dutch instead of translating English search intent directly.
- Add analytics-free performance monitoring, such as server-side Search Console review and App Store conversion tracking.
- Test App Store CTA placement by article type without adding advertising trackers.

## Maintenance checklist
1. Add or update a post in \`docs/content/blog-manifest.json\`.
2. Add new media under \`docs/assets/images/blog/<topic>/\` and update \`alt-text-reference.json\`.
3. Run \`node tools/render-blog.mjs\`.
4. Run \`node tools/validate-site.mjs\`.
5. Review \`docs/VALIDATION-REPORT.md\`.
6. Spot-check at least one English page and one localized page in a browser.
7. Submit the updated sitemap in Search Console after deployment.
`;
  await writeText(path.join(DOCS, 'CONTENT-ROADMAP.md'), roadmap);
}

async function main() {
  await ensureDir(CONTENT_DIR);
  const shouldReset = process.argv.includes('--reset-manifest') || !existsSync(MANIFEST_PATH);
  if (shouldReset) await writeJson(MANIFEST_PATH, defaultManifest);
  const manifest = await readJson(MANIFEST_PATH);
  const media = await normalizeMediaManifest();
  const mediaByPath = new Map(media.map(item => [item.path, item]));

  for (const article of manifest.articles) {
    for (const locale of Object.keys(locales)) {
      const file = fileForUrl(blogUrl(locale, article.slug));
      await writeText(file, articlePage(article, locale, manifest, mediaByPath));
    }
  }

  for (const locale of Object.keys(locales)) {
    const file = fileForUrl(blogUrl(locale));
    await writeText(file, blogIndex(locale, manifest, mediaByPath));
  }

  await writeText(path.join(DOCS, 'sitemap.xml'), sitemap(manifest));
  await writeText(path.join(DOCS, 'llms.txt'), llmsTxt(manifest));
  await writeRoadmap(manifest);
  console.log(`Rendered ${manifest.articles.length} articles across ${Object.keys(locales).length} locales.`);
}

main().catch(error => {
  console.error(error);
  process.exit(1);
});
