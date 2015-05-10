puts '['
10000.times do |i|
  f = i.to_f
  puts %Q!\t{"x":#{9*f+f/100000},"y":#{-f+f/100000},"string":"#{"mmm%xaaaaaaaa"%(i%1000)}","value":#{[true,'"foo\nbar"',i][i%3]}},!
end
puts 'false'
puts ']'
