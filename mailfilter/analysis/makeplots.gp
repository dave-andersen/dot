set logscale x
set logscale y
set xtics nomirror
set ytics nomirror
set border 3
set key bottom left
set xlabel "Message Size (KB)"
set ylabel "Fraction of Messages"
set terminal postscript eps enhanced "NimbusSanL-Regu" 22 fontfile "uhvr8a.pfb"
set output "wholesize_cdf.eps"
plot [0.5:] "wholesize.cdf" using ($1/1024):(1-$2) title "Mail size CCDF" with lines

set terminal postscript eps 22 color
set output "wholesize_cdf.color.eps"
plot [0.5:] "wholesize.cdf" using 1:(1-$2) title "Mail size CCDF" with lines lw 3


set logscale x
set logscale y
set xlabel "Number of Duplicates"
set ylabel "Number of Message Bodies"
set key top right
set terminal postscript eps monochrome enhanced "NimbusSanL-Regu" 22 fontfile "uhvr8a.pfb"
set output "sharedbodies_hist.eps"
plot [0.5:] [0.5:400000] "sharedbodies.hist" notitle with boxes

set terminal postscript eps 22 color
set output "sharedbodies_hist.color.eps"
plot [0.5:] [0.5:400000] "sharedbodies.hist" notitle with boxes lw 2
