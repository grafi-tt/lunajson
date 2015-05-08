puts '['
1000000.times do |i|
  f = i.to_f
  puts %Q!\t{"x":#{f+f/1000000},"y":#{-f+f/1000000},"aaaaaaaa":#{[true,'"foo\nbar"'][i%2]}},!
end
puts 'false'
puts ']'
