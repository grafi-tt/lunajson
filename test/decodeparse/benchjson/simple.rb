puts '['
10000.times do |i|
  f = i.to_f
  puts %Q!\t{"x":#{9*f+f/100000},"y":#{-f+f/100000},"#{"mmm%xaaaaaaaa"%(i%1000)}":#{[true,'"foobar"'][i%2]},"iiiii":#{i}},!
end
puts 'false'
puts ']'
