## vi_expander.rb
# This is a command-line wrapper for the DiacriticExpander class tied to the
#  Vietnamese language.

require_relative 'diacritic_expander'

if ARGV.empty?
  puts "  Usage: ruby vi_expander.rb <regexp|keywords> <word or phrase to expand> <case sensitive? (true|false)>"
  puts "      Example (returns regular expression): ruby vi_expander.rb regexp \"sach\""
  puts "      Example (return keywords): ruby vi_expander.rb keywords \"dang so\" true"
  exit
end

mode, word_or_phrase, case_sensitive = ARGV

case_sensitive = case_sensitive == "true" ? true : false

e = DiacriticExpander.new

case mode.downcase.to_sym
  when :regexp
    puts e.expand_to_regexp(word_or_phrase, case_sensitive).inspect
  when :keywords
    puts e.expand_to_keywords(word_or_phrase, case_sensitive).join(", ")
end