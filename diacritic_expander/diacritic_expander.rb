class DiacriticExpander
  attr_reader :language
  def initialize(language=:vi)
    @language = language
    load_charset
  end

  def expand_to_regexp(word_or_phrase, case_sensitive=false)
    expand word_or_phrase, :regexp, case_sensitive
  end

  def expand_to_keywords(word_or_phrase, case_sensitive=false)
    expand word_or_phrase, :keywords, case_sensitive
  end

  def self.create_charset_file(path_to_file="unicode_charset.txt", language=:vi)
    # Expects a two column, tab-delimited file including unicode hex and letter description
    input_file = File.open(path_to_file)
    output_file = File.open("charset.#{ language }.txt", "w")
    
    input_file.each do |line|
      char, description = line.split("\t")
      char.gsub!("U+", "")
      char = [char.hex].pack "U"

      # match = description.match /LATIN (\w+) LETTER (\w) WITH ((\w+)( AND ([\w ]+))?)/i
      match = description.match /LATIN (\w+) LETTER (\w) WITH ([\w ]+)/i
      next unless match

      letter_case, letter, diacritics = match.captures
      diacritics = diacritics.split(" AND ").collect {|d| d.gsub(" ", "_").downcase }
      diacritics.sort!

      output_file.puts [char, letter_case.downcase, letter.downcase, diacritics.join(" ")].join("\t")
    end

    input_file.close
    output_file.close
  end

protected
  def load_charset
    file = File.open("charset.#{ @language }.txt")
    @letters_by_latin = {}
    @characters = {}

    file.each do |line|
      char, letter_case, letter, diacritics = line.split("\t")
      diacritics = diacritics.split(" ").collect { |d| d.to_sym }
      letter_case = letter_case == "small" ? :lower : :upper
      @letters_by_latin[letter] ||= { :all => [], :lower => [], :upper => []}
      @letters_by_latin[letter][:all] << char
      @letters_by_latin[letter][letter_case] << char
      @characters[char] = { :letter => letter, :diacritics => diacritics, :case => letter_case }
    end

    @letters_by_latin.keys.each do |letter|
      @characters[letter] = { :letter => letter, :case => :lower }
      @characters[letter.upcase] = { :letter => letter, :case => :upper }
      @letters_by_latin[letter][:all] += [letter.upcase, letter]
      @letters_by_latin[letter][:lower] << letter
      @letters_by_latin[letter][:upper] << letter.upcase
    end
  end

  def expand(word_or_phrase, mode, case_sensitive=false)
    words = []
    variable_words = []
    regexp_components = []
    phrases = []

    word_or_phrase.split(" ").each do |word|
      regexp = ""
      proto = []
      variable_chars = []
      current_words = []
      word.each_char do |char|
        info = @characters[char]
        # puts char
        # puts info.inspect
        unless info
          regexp += char
          proto << char
        else
          if case_sensitive
            letter_case = info[:case]
          elsif mode == :regexp
            letter_case = :lower
          else
            letter_case = :all
          end
          proto << nil
          letters = @letters_by_latin[info[:letter]][letter_case]
          variable_chars << letters
          regexp += "[#{ letters.join("") }]"
        end
      end
      regexp_components << regexp
      next if mode == :regexp
      if variable_chars.length == 0
        words << word
        next
      else
        words << nil
      end

      first = variable_chars.shift
      combinations = first.product(*variable_chars)

      combinations.each do |combo|
        full_word = proto.collect { |l| l ? l : combo.shift }.join("")
        current_words << full_word
        # print full_word + ", "
      end
      # puts combinations.length
      variable_words << current_words
    end

    # repeat logic used for letter combinations here, but for words
    # TODO: determine if we can optimize by removing the else here
    if mode == :keywords && variable_words.length > 0
      first = variable_words.shift
      combinations = first.product(*variable_words)
      combinations.each do |combo|
        phrases << words.collect { |w| w ? w : combo.shift }.join(" ")
      end
    else
      phrases << words.join(" ")
    end
    # puts combinations.length

    # TODO: Should this return strings or objects?
    if mode == :regexp
      regexp = regexp_components.join("\\s+")
      return case_sensitive ? regexp : "(?i)#{ regexp }"
      # return case_sensitive ? Regexp.new(regexp) : Regexp.new(regexp, Regexp::IGNORECASE)
    else
      return phrases
    end
  end
end