set terminal png size 800, 400 font "Nimbus Sans L,12"
set title "Encoding Performances"
set style data histogram
set grid ytics
set style fill solid border -1
set ylabel "Elapased Time in Seconds"
plot 'encode-simple.dat' using 2:xtic(1) title col, \
                      '' using 3:xtic(1) title col lc 3, \
                      '' using 4:xtic(1) title col lc 5
