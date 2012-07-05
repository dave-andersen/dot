#!/usr/bin/perl -w

use strict 'vars';
use Gtk2;
use Gtk2::Gdk::Keysyms;

use constant TRUE => 1;
use constant FALSE => 0;

my $GRAN_MSEC = 450;
my $GRAN_SEC = 1;

my $pbutton = undef;
my $paused = 0;
my $loop = 0;
my $tag = undef;

my @pal = ('blue', 'red', 'green', 'brown', 'purple');
my @pal_gc = ();
my @instances;

sub handler
{
    my $res = 0;

    foreach (@instances) {
        next if (!$_->[1]);
        $_->[1] = $_->[0]->_handler;
        $res = 1;
    }
    if (!$res && $loop) {
        Glib::Timeout->add(3000, sub { restart(); return 0 });
    }
    return $res;
}

sub pause_handler
{
    my ($button) = @_;

    $paused = not $paused;
    if ($paused) {
        $button->set_label('gtk-media-play');
    }
    else {
        $button->set_label('gtk-media-pause');
    }
}

sub run_demo
{
    my $i = 0;
    my $new_y = 0;
    my $new_x = 0;

    # Create an accel group for keybindings
    my $accel_group = Gtk2::AccelGroup->new;
    $accel_group->connect($Gtk2::Gdk::Keysyms{'Q'}, [], 'visible',
        sub { exit(0); } );
    $accel_group->connect($Gtk2::Gdk::Keysyms{'R'}, [], 'visible',
        sub { restart(); } );
    $accel_group->connect($Gtk2::Gdk::Keysyms{space}, [], 'visible',
        sub { pause_handler($pbutton); } );

    foreach (@ARGV) {
        my $f = SetSim->new($_);
        push(@instances, [$f, 1]);
        $f->go;

        my ($w, $h) = $f->get_size();
        $new_y = $h if ($new_y < $h);
        $new_x = $w;

        $f->add_accel_group($accel_group);

        $i++;
    }

## Let Window Manager do this for now
#
#    # Set geometry of windows
#    my $y_pos = 0;
#    foreach (@instances) {
#        # These line for equal height windows
#        $_->[0]->resize($new_x, $new_y);
#        $_->[0]->parse_geometry("+0+$y_pos");
#        $y_pos += $new_y + 23;  # allow room for titlebar
#
#        # These line for minimal height windows
#        $_->[0]->parse_geometry("+0+$y_pos");
#        my ($w, $h) = $_->[0]->get_size();
#        $y_pos += $h + 30;  # allow room for titlebar
#    }

    $tag = Glib::Timeout->add($GRAN_MSEC, \&handler);
}

sub restart
{
    Glib::Source->remove($tag) if $tag;
    foreach (@instances) {
        #my $e = pop(@instances);
        #$e->[0]->destroy();
        #undef $e->[0];

        $_->[1] = 1;
        $_->[0]->restart;
    }
    $tag = Glib::Timeout->add($GRAN_MSEC, \&handler);
    $paused = 0;
    #run_demo();
}

sub create_main_window
{
    my $win = Gtk2::Window->new('toplevel');

    # Create a pause/play button and quit button
    my $bbox = Gtk2::VButtonBox->new;
    my $check = Gtk2::CheckButton->new("Loop?");
    my $qbutton = Gtk2::Button->new_from_stock('gtk-quit');
    $pbutton = Gtk2::Button->new_from_stock('gtk-media-pause');
    my $rbutton = Gtk2::Button->new_from_stock('gtk-media-rewind');
    $check->signal_connect_swapped (toggled => sub { $loop = not $loop; });
    $qbutton->signal_connect_swapped (clicked => sub { exit(0); });
    $rbutton->signal_connect_swapped (clicked => sub { restart(); });
    $pbutton->signal_connect_swapped (clicked => \&pause_handler, $pbutton);
    $bbox->set_spacing(10);
    $bbox->set_border_width(10);
    $bbox->add($pbutton);
    $bbox->add($rbutton);
    $bbox->add($qbutton);
    $bbox->add($check);
    $win->add($bbox);

    my ($w, $h) = $win->get_size();
    $win->parse_geometry("-$w+0");
    $win->signal_connect ("destroy", sub { Gtk2->main_quit; });
    $win->show_all();
}

# main ####################################################################

if ($#ARGV < 0) {
    die "$0 <animation filename>\n";
}

Gtk2->init;

create_main_window();
run_demo();

Gtk2->main;

############################################################################

package EventSource;

use strict 'vars';
use warnings;

sub new
{
    my $proto = shift;
    my $filename = shift || die "Need filename argument";
    my $class = ref($proto) || $proto;
    my $self = {};
    $self->{filename} = $filename;
    $self->{linebuf} = undef;
    $self->{finished} = 0;
    $self->{numsrcs} = 0;
    $self->{maxblocks} = -1;
    $self->{fh} = "$filename";
    bless ($self, $class);
    return $self;
}

sub init_trace
{
    my ($self, $iptosrc, $srcinfo) = @_;
    my $fh = $self->{fh};

    print "Start init $self->{filename}\n";

    if (!open ($fh, $self->{filename})) {
        die "could not open $self->{filename} for reading";
    }

    my $line = <$fh>;

    if ($line =~ /^Number of sources = (\d+)/) {
        $self->{numsrcs} = $1;
        print "Number of sources $self->{numsrcs}\n";
    }
    else {
        die "Problem in config file\n";
    }

    my $i;
    my $j;

    for ($i = 0; $i < $self->{numsrcs}; $i++) {
        $line = <$fh>;
        chomp $line;
        my ($ip, $port, $num, @rest) = split(/ +/, $line);
        $iptosrc->{"$ip:$port"} = $i;
        if ($self->{maxblocks} < $num) {
            $self->{maxblocks} = $num
        }
        $srcinfo->[$i] = ();
        $srcinfo->[$i]{ip} = $ip;
        $srcinfo->[$i]{port} = $port;
        $srcinfo->[$i]{avail} = 0;
        $srcinfo->[$i]{bitmap} = [];
        for ($j = 0; $j < $num; $j++) {
            push(@{$srcinfo->[$i]{bitmap}}, $rest[$j]);
            $srcinfo->[$i]{avail}++ if $rest[$j] == 1;
        }
    }

    $line = <$fh>;
    $self->{linebuf} = $line;

    chomp $line;
    my ($start, @rest) = split(/ +/,$line);

    print "Finishing init $self->{filename} -- ";
    print "Start time = $start\n";

    return $start;
}

sub get_event
{
    my ($self, $t) = @_;
    my $fh = $self->{fh};

    my $line;
    if ($self->{linebuf}) {
        $line = $self->{linebuf};
        $self->{linebuf} = undef;
    }
    else {
        $line = <$fh>;
    }

    if (not $line) {
        $self->{finished} = 1;
	close($fh);
        return ();
    }

    chomp $line;
    my @allwords = split(/ +/, $line);

    my %event;
    $event{time} = $allwords[0];
    $event{ip} = $allwords[1];
    $event{port} = $allwords[2];
    $event{blocknum} = $allwords[3];

    if ($event{time} > $t) {
        $self->{linebuf} = $line;
        return ();
    }
    return %event;
}

############################################################################

package SetSim;

use strict 'vars';
use warnings;

use base 'Gtk2::Window';

use constant TRUE => 1;
use constant FALSE => 0;

sub new
{
    my $proto = shift;
    my $filename = shift || die "Need filename argument";
    my $class = ref($proto) || $proto;
    my $self = Gtk2::Window->new ('toplevel');
    $self->{filename} = $filename;
    $self->{eventsource} = undef;
    $self->{iptosrc} = {};
    $self->{srcinfo} = [];
    $self->{srclabel} = [];
    $self->{srccount} = [];
    $self->{srcbar} = [];
    $self->{recvda} = undef;
    $self->{recvpixmap} = undef;
    $self->{recvblocks} = 0;
    $self->{time_label} = undef;
    $self->{clock} = 0;
    $self->{curtime} = 0;
    $self->{srctab1} = undef;


    bless ($self, $class);
    return $self;
}

sub restart
{
    my ($self) = @_;

    $self->{eventsource} = undef;
    $self->{iptosrc} = {};
    $self->{srcinfo} = [];

    $self->{eventsource} = EventSource->new($self->{filename});
    $self->{curtime} =
        $self->{eventsource}->init_trace($self->{iptosrc}, $self->{srcinfo});

    $self->{srclabel} = [];
    $self->{srccount} = [];
    $self->{srcbar} = [];
    add_count_table($self, $self->{srctab1});

    clear_bitmap($self, $self->{recvda});

    $self->{recvblocks} = 0;
    $self->{clock} = 0;

    my $color = Gtk2::Gdk::Color->parse ('black');
    $self->{time_label}->modify_fg (normal => $color);

    update_clock_display($self);
}

sub go
{
    my ($self) = @_;

    $self->{eventsource} = EventSource->new($self->{filename});
    $self->{curtime} =
        $self->{eventsource}->init_trace($self->{iptosrc}, $self->{srcinfo});

    my $window = $self;
    my $eventsource = $self->{eventsource};

    # Create application window
    $window->set_title ($self->{filename});
    $window->set_border_width(10);
    $window->set_size_request (-1, -1);
    $window->signal_connect ("delete_event", sub { return TRUE; });

    my $vbox = Gtk2::VBox->new (FALSE, 0);

    $window->add ($vbox);

    # Create a label/title
    my $font_desc = Gtk2::Pango::FontDescription->from_string
        ("Nimbus bold 16");
    my $label = Gtk2::Label->new
        ("Similarity-Enhanced Transfer (SET) Demo -- " . $self->{filename});
    $label->modify_font ($font_desc);
    $vbox->pack_start ($label, FALSE, FALSE, 2);

    # Create a horizontal line to separate from title
    my $sep = Gtk2::HSeparator->new;
    $vbox->pack_start ($sep, FALSE, FALSE, 5);

    # Create two side-by-side tables for source names and bitmaps;
    # this is necessary because of resizing issues with the tables
    my $hbox = Gtk2::HBox->new;

    my $titletab = Gtk2::Table->new ($eventsource->{numsrcs}, 2, TRUE);
    my $bitmaptab = Gtk2::Table->new ($eventsource->{numsrcs},
        $eventsource->{maxblocks}, TRUE);
    add_bitmaps($self, $titletab, $bitmaptab);

    $hbox->pack_start ($titletab, FALSE, FALSE, 0);
    $hbox->pack_start ($bitmaptab, TRUE, TRUE, 40);
    $vbox->pack_start ($hbox, FALSE, FALSE, 10);
    
    # Create a table for source count
    my $srctab1 = Gtk2::Table->new ($eventsource->{numsrcs}, 3, FALSE);
    $self->{srctab1} = $srctab1;
    add_count_table($self, $srctab1);
    $vbox->pack_start ($srctab1, FALSE, FALSE, 0);

    # Create an area to show receiver chunks
    my $rframe = Gtk2::Frame->new ("Receiver");
    $rframe->set_label_align(0.5, 0.5);

    # XXX: This isn't exactly correct; first arg should be number of
    # blocks in the target file
    $rframe->set_size_request ($eventsource->{maxblocks}+15, 45);
    $self->{recvda} = add_recv_table($self);
    $rframe->add ($self->{recvda});

    my $al = Gtk2::Alignment->new(0.0, 1.0, 0.0, 0.0);
    $al->add($rframe);
    #$vbox->pack_start ($al, TRUE, TRUE, 10);

    # Create a stopwatch counting up time
    my $cframe = Gtk2::Frame->new ("Time Elapsed");
    $cframe->set_label_align(0.5, 0.5);
    my $clock_box = Gtk2::EventBox->new;
    $font_desc = Gtk2::Pango::FontDescription->from_string ("Nimbus bold 25");
    $self->{time_label} = Gtk2::Label->new;
    $self->{time_label}->modify_font ($font_desc);
    $self->{time_label}->set_size_request (125);
    $clock_box->add ($self->{time_label});
    $cframe->add ($clock_box);

    $hbox = Gtk2::HBox->new;
    $hbox->pack_start ($al, TRUE, TRUE, 0);
    $hbox->pack_start ($cframe, TRUE, FALSE, 0);

    $al = Gtk2::Alignment->new(0.5, 1.0, 1.0, 0.0);
    $al->add($hbox);
    $vbox->pack_start ($al, TRUE, TRUE, 0);

    $window->show_all;
}

sub update_count_table
{
    my ($self, $index) = @_;
    my $srclabel = $self->{srclabel};
    my $srccount = $self->{srccount};

    $$srccount[$index]++;
    $$srclabel[$index]->set_text(sprintf("% 5s", $$srccount[$index]));
}

sub update_progress_bars
{
    my ($self) = @_;
    my $srcbar = $self->{srcbar};
    my $srccount = $self->{srccount};

    my $i = 0;
    foreach (@$srccount) {
        my $c = $_;
        next if $self->{recvblocks} == 0;
        $$srcbar[$i]->set_fraction($c/$self->{recvblocks});
        $$srcbar[$i]->set_text(sprintf("%3.0f%%", $c/$self->{recvblocks}*100));
        $i++;
    }
}

sub update_clock_display
{
    my ($self) = @_;

    my $s = $self->{clock};
    my $m = int (int($s) / int(60));
    $s = $s % 60;

    $m = sprintf("%02.0f", $m);
    $s = sprintf("%02.0f", $s);
    $self->{time_label}->set_text("$m:$s");
}

sub update_recv_display
{
    my ($self, $index, $blocknum) = @_;

    $self->{recvblocks}++;

    draw_chunk($self, $self->{recvda}, $index, $blocknum+5, 3);
}

sub _handler
{
    my ($self) = @_;
    my $eventsource = $self->{eventsource};
    my $iptosrc = $self->{iptosrc};

    return 1 if ($paused);

    $self->{curtime} += $GRAN_SEC;
    $self->{clock} += $GRAN_SEC;

    update_clock_display ($self);

    #print "$self->{filename}  ";
    #print "Time now is $self->{curtime}\n";

    my %event;
    while ((%event = $eventsource->get_event($self->{curtime}))) {
	my $key = "$event{ip}:$event{port}";
	
	if (!defined $iptosrc->{$key}) {
	    print "Problem in number of sources\n";
	    die;
	}
        my ($index, $ip) = $iptosrc->{$key};
        update_recv_display ($self, $index, $event{blocknum});
	update_count_table ($self, $index);
    }
    update_progress_bars ($self);

    if ($eventsource->{finished}) {
        my $color = Gtk2::Gdk::Color->parse ('red');
        $self->{time_label}->modify_fg (normal => $color);
        return 0;
    }

    return 1;
}

###########################

sub add_recv_table
{
    my ($self) = @_;
    my $eventsource = $self->{eventsource};

    my $da = Gtk2::DrawingArea->new;
    $self->{da} = $da;
    $da->set_size_request($eventsource->{maxblocks}+10, 45);
    $da->signal_connect (expose_event => \&expose_event, $self);
    $da->signal_connect (configure_event => \&configure_event, $self);
    return $da;
}

sub add_count_table
{
    my ($self, $table) = @_;
    my $srclabel = $self->{srclabel};
    my @srcinfo = @{$self->{srcinfo}};
    my $srccount = $self->{srccount};
    my $srcbar = $self->{srcbar};

    my $i = 0;
    
    foreach (@srcinfo) {
        my $ip = $_->{ip};

        # add title
        my $event_box = Gtk2::EventBox->new;
        my $label = Gtk2::Label->new ("Source " . ($i+1) . ":");
        $event_box->add ($label);
        $label->show;
        $event_box->show;

        $table->attach ($event_box, 0, 1, $i, $i+1,
			['fill'], ['expand'], 0, 3);

	# add count
        $event_box = Gtk2::EventBox->new;
        $label = Gtk2::Label->new (sprintf("% 5s", "0"));
        $event_box->add ($label);
        $label->show;
        $event_box->show;
	
	push(@$srclabel, $label);
	push(@$srccount, 0);

        $table->attach ($event_box, 1, 2, $i, $i+1,
			['fill'], ['expand'], 19, 3);

        # add progress bar
        my $pb = Gtk2::ProgressBar->new;
        my $color = Gtk2::Gdk::Color->parse ($pal[$i]);
        $pb->modify_fg (normal => $color);
        $pb->set_text ("0%");
        $pb->show;

        push(@$srcbar, $pb);

        $table->attach ($pb, 2, 3, $i, $i+1,
                        ['fill'], ['expand'], 42, 3);
	
	$i++;
    }
}

sub add_bitmaps
{
    my ($self, $title_tab, $bitmap_tab) = @_;
    my @srcinfo = @{$self->{srcinfo}};

    my $i = 0;

    foreach (@srcinfo) {
        my @bitmap = @{$_->{bitmap}};
        my $ip = $_->{ip};
        my $avail = $_->{avail};

        # add title
        my $event_box = Gtk2::EventBox->new;
        my $label = Gtk2::Label->new ("Source " . ($i+1) . ":");
        $event_box->add ($label);
        $label->show;
        $event_box->show;

        $title_tab->attach ($event_box, 0, 1, $i, $i+1,
                            ['fill'], ['fill'], 0, 3);

	# add available block count
        $event_box = Gtk2::EventBox->new;
        $label = Gtk2::Label->new (sprintf("% 5s", $avail));
        $event_box->add ($label);
        $label->show;
        $event_box->show;
	
        $title_tab->attach ($event_box, 1, 2, $i, $i+1,
		  	    ['fill'], ['fill'], 0, 3);

        # add bitmap
        my $j = 0;
        foreach (@bitmap) {
            my $showit = $_;
            my $event_box = Gtk2::EventBox->new;
            my $color;
            if ($showit) {
                $color = Gtk2::Gdk::Color->parse ($pal[$i]);
            }
            else {
		$color = undef;
            }
            $event_box->modify_bg (normal => $color) if $color;
            $event_box->set_size_request(1, 19);
            $event_box->show;

            $bitmap_tab->attach ($event_box, $j, $j+1, $i, $i+1,
                                 ['fill'], ['fill'], 0, 2);
            $j++;
        }
        $i++;
    }
}

# Create a new pixmap of the appropriate size to store our scribbles
sub configure_event
{
  my ($widget, $event, $self) = @_;

  if (not $self->{recvpixmap}) {
      $self->{recvpixmap} = Gtk2::Gdk::Pixmap->new ($widget->window,
                                                    $widget->allocation->width,
                                                    $widget->allocation->height,
                                                    -1);

      # Initialize the pixmap to the background color
      $self->{recvpixmap}->draw_rectangle ($widget->style->bg_gc('normal'),
                                           TRUE,
                                           0, 0,
                                           $widget->allocation->width,
                                           $widget->allocation->height);
  }

  # We've handled the configure event, no need for further processing.
  return TRUE;
}

# Redraw the screen from the pixmap
sub expose_event
{
  my ($widget, $event, $self) = @_;

  # We use the "foreground GC" for the widget since it already exists,
  # but honestly any GC would work. The only thing to worry about
  # is whether the GC has an inappropriate clip region set.
  #
  $widget->window->draw_drawable ($widget->style->fg_gc($widget->state),
                                  $self->{recvpixmap},
                                  # Only copy the area that was exposed.
                                  $event->area->x, $event->area->y,
                                  $event->area->x, $event->area->y,
                                  $event->area->width, $event->area->height);
  
  return FALSE;
}

sub draw_chunk
{
  my ($self, $widget, $color, $x, $y) = @_;

  return FALSE unless defined $self->{recvpixmap};

  if (not defined $pal_gc[$color]) {
      my $gc = Gtk2::Gdk::GC->new($self->{recvpixmap});
      $gc->set_rgb_fg_color(Gtk2::Gdk::Color->parse($pal[$color]));
      $pal_gc[$color] = $gc;
  }

  my $update_rect = Gtk2::Gdk::Rectangle->new ($x, $y, 1, 20);

  # Paint to the pixmap, where we store our state
  $self->{recvpixmap}->draw_rectangle ($pal_gc[$color], TRUE, $update_rect->values);

  # Now invalidate the affected region of the drawing area.
  $widget->window->invalidate_rect ($update_rect, FALSE);
}

sub clear_bitmap
{
  my ($self, $widget) = @_;

  return FALSE unless defined $self->{recvpixmap};

  my $update_rect = Gtk2::Gdk::Rectangle->new (0, 0,
                                               $widget->allocation->width,
                                               $widget->allocation->height);

  # Paint to the pixmap, where we store our state
  $self->{recvpixmap}->draw_rectangle ($widget->style->bg_gc('normal'),
                                       TRUE, $update_rect->values);

  # Now invalidate the affected region of the drawing area.
  $widget->window->invalidate_rect ($update_rect, FALSE);
}

#########
# original (c) notice
#########
#
# GTK - The GIMP Toolkit
# Copyright (C) 1995-1997 Peter Mattis, Spencer Kimball and Josh MacDonald
#
# Copyright (C) 2003 by the gtk2-perl team (see the file AUTHORS for the full
# list)
# 
# This library is free software; you can redistribute it and/or modify it under
# the terms of the GNU Library General Public License as published by the Free
# Software Foundation; either version 2.1 of the License, or (at your option)
# any later version.
# 
# This library is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU Library General Public License for
# more details.
# 
# You should have received a copy of the GNU Library General Public License
# along with this library; if not, write to the Free Software Foundation, Inc.,
# 59 Temple Place - Suite 330, Boston, MA  02111-1307  USA.
#
# $Header: /cvsroot/gtk2-perl/gtk2-perl-xs/Gtk2/examples/scribble.pl,v 1.8 2003/10/19 02:59:43 muppetman Exp $
#

# this was originally gtk-2.2.0/examples/scribble-simple/scribble-simple.c
# ported to gtk2-perl by muppet


