require_relative 'diacritic_expander'

DiacriticExpander.create_charset_file

e = DiacriticExpander.new

puts e.expand_to_regexp("minh thuan")

puts e.expand_to_keywords("minh thuan")