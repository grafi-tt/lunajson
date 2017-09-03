set terminal png size 800, 400 font "Nimbus Sans L,12"
set title "Decoding Performances"
set style data histogram
set grid ytics
set style fill solid border -1
set ylabel "Elapased Time in Seconds"
plot 'decode-simple.dat' using 2:xtic(1) title col, \
                      '' using 3:xtic(1) title col, \
                      '' using 4:xtic(1) title col, \
                      '' using 5:xtic(1) title col, \
                      '' using 6:xtic(1) title col
