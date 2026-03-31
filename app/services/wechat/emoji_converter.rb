class Wechat::EmojiConverter
  # WeChat built-in emoji codes to Unicode emoji/text mapping
  # Based on WeChat's standard emoji system
  WECHAT_EMOJI_MAP = {
    # Happy/Positive emotions
    '/:)' => '😊',           # Smile
    '/:-)' => '😊',          # Smile
    '/::)' => '😂',          # Laugh/Joy
    '/:8-)' => '😎',         # Cool with sunglasses
    '/:D' => '😃',           # Big smile
    '/:|-)' => '😉',         # Wink
    '/:P' => '😛',           # Tongue out
    '/::P' => '😜',          # Wink with tongue

    # Sad/Negative emotions
    '/:(' => '😢',           # Sad
    '/::-(' => '😢',         # Sad
    '/::(/' => '😭',         # Crying
    '/::T' => '😤',          # Huffing
    '/::X' => '😵',          # Dizzy/knocked out
    '/:@' => '😠',           # Angry
    '/::@' => '😡',          # Very angry
    '/::<' => '😰',          # Anxious
    '/::-S' => '😖',         # Confounded

    # Other expressions
    '/:?' => '🤔',           # Thinking
    '/:o' => '😮',           # Surprised
    '/::o' => '😲',          # Shocked
    '/:Z' => '😴',           # Sleeping
    '/::Z' => '💤',          # Sleep symbol
    '/:kiss' => '😘',        # Kiss
    '/:love' => '😍',        # Love eyes
    '/:rose' => '🌹',        # Rose
    '/:beer' => '🍺',        # Beer
    '/:coffee' => '☕',       # Coffee
    '/:cake' => '🎂',        # Cake
    '/:pizza' => '🍕',       # Pizza
    '/:heart' => '💖',       # Heart
    '/:handshake' => '🤝',   # Handshake
    '/:thumbsup' => '👍',    # Thumbs up
    '/:thumbsdown' => '👎',  # Thumbs down
    '/:clap' => '👏',        # Clapping
    '/:victory' => '✌️',      # Victory sign

    # Common WeChat specific ones
    '/::,' => '😅',          # Sweat smile
    '/::!' => '😱',          # Scream
    '/::$' => '🤑',          # Money face
    '/::&' => '🤐',          # Zip mouth
    '/::*' => '😗',          # Kiss face
    '/::#' => '😬',          # Grimace
    '/::^' => '🙄',          # Eye roll
  }.freeze

  def self.convert_emojis(text)
    return text if text.blank?

    converted_text = text.dup

    # Sort by length (longest first) to avoid partial replacements
    WECHAT_EMOJI_MAP.keys.sort_by(&:length).reverse.each do |wechat_code|
      unicode_emoji = WECHAT_EMOJI_MAP[wechat_code]
      converted_text = converted_text.gsub(wechat_code, unicode_emoji)
    end

    converted_text
  end

  def self.convert_with_fallback(text)
    return text if text.blank?

    converted_text = text.dup

    # First pass: convert known emojis
    converted_text = convert_emojis(converted_text)

    # Second pass: convert unknown WeChat emoji codes to readable text
    # Pattern matches /:xyz or /::xyz
    converted_text = converted_text.gsub(%r{/::?([a-zA-Z0-9\-_]+)}) do |match|
      code = Regexp.last_match(1)
      "[WeChat Emoji: #{code}]"
    end

    converted_text
  end

  # For debugging: extract all WeChat emoji codes from text
  def self.extract_wechat_codes(text)
    return [] if text.blank?

    text.scan(%r{/::?[a-zA-Z0-9\-_\(\)]+}).uniq
  end
end
