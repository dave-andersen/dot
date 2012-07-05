#!/usr/bin/python

# points.py

import sys
import math
import time
from PyQt4 import QtGui
from PyQt4 import QtCore
from QPlot import QPlot
from QBitmap import QBitmap
       

class MainFrame(QtGui.QWidget):
    def __init__(self, parent = None):
        QtGui.QWidget.__init__(self, parent)

        self.setGeometry(300, 300, 800, 600)
        self.setWindowTitle('Intel Open House 2008')
        self.setFont(QtGui.QFont("Arial", 15, QtGui.QFont.Bold))
        
        layout = QtGui.QGridLayout(self)
        
        figure_frame = QtGui.QFrame()
        figure_frame.setLayout(QtGui.QGridLayout())
        self.layout().addWidget(figure_frame, 0, 0)

        self.strategies = ["Rarest-Random", "Sequential", "Hybrid"]
        groups = {}
        self.figures = {}
        self.bitmaps = {}
        self.pbars = {}
        self.pb = {}
        ### pre-read the logs
        self.logs={}
        self.max_time = {}
        for s in self.strategies:
            self.max_time[s] = -1
            self.logs[s] = open('trace/%s/log-node3-chunk'%(s), 'r')
            for l in self.logs[s]:
                t = float(l.split(' ')[0])
                if t > self.max_time[s]:
                    self.max_time[s] = int(math.ceil(t))
            self.logs[s].seek(0)
        print self.max_time
            
        for s in self.strategies:
            groups[s] = QtGui.QGroupBox(figure_frame)
            groups[s].setTitle(s)
            groups[s].setAlignment(QtCore.Qt.AlignHCenter)
            groups[s].setLayout(QtGui.QVBoxLayout())      
            
            
            self.figures[s] = QPlot(groups[s])
            self.pb[s] = QtGui.QLabel(groups[s])
            self.pb[s].setFixedHeight(50)
            self.pbars[s] = QtGui.QLabel(groups[s])
            self.pbars[s].setFixedHeight(50)
            self.bitmaps[s] = QBitmap(groups[s], 291)
            
            groups[s].layout().addWidget(self.figures[s])
            groups[s].layout().addWidget(self.bitmaps[s])
            groups[s].layout().addWidget(self.pb[s])
            groups[s].layout().addWidget(self.pbars[s])
            
            figure_frame.layout().addWidget(groups[s], 0, self.strategies.index(s))
            
        control_frame = QtGui.QGroupBox(self)
        control_frame.setTitle("Control")
        control_frame.setFixedHeight(150)
        control_frame.setLayout(QtGui.QHBoxLayout())
        control_frame.layout().addStretch(1)
        self.layout().addWidget(control_frame, 1, 0)
        
        self.titles={'play':'&Play', 'pause':'Pa&use', 'reset':'&Reset',\
                     'loop':'&Loop', 'quit':'&Quit'}
        self.play = QtGui.QPushButton(self.titles['play'], control_frame)
        self.play.setFixedSize(100, 35)
        
        self.reset = QtGui.QPushButton(self.titles['reset'], control_frame)
        self.reset.setFixedSize(100, 35)

        self.loop = QtGui.QPushButton(self.titles['loop'], control_frame)
        self.loop.setFixedSize(100, 35)
        
        self.quit = QtGui.QPushButton(self.titles['quit'], control_frame)
        self.quit.setFixedSize(100, 35)        
        
        replay_slider_group = QtGui.QGroupBox(control_frame)
        replay_slider_group.setTitle("Replay Speed")
        replay_slider_group.setLayout(QtGui.QVBoxLayout())
        self.replay_slider = QtGui.QSlider(QtCore.Qt.Horizontal, replay_slider_group)
        self.replay_slider.setRange(1, 100)
        self.replay_slider.setValue((self.replay_slider.minimum()+self.replay_slider.maximum())/2)
        replay_slider_group.layout().addWidget(self.replay_slider)
        
        pbar_group = QtGui.QGroupBox(control_frame)
        pbar_group.setTitle("Replay Progress")
        pbar_group.setLayout(QtGui.QVBoxLayout())
        self.replay_pbar = QtGui.QProgressBar(pbar_group)
        self.replay_pbar.setRange(0, max(self.max_time.values()))
        pbar_group.layout().addWidget(self.replay_pbar)

        self.playback_slider_group = QtGui.QGroupBox(control_frame)
        self.playback_slider_group.setTitle("Playback Rate")
        self.playback_slider_group.setLayout(QtGui.QVBoxLayout())
        self.playback_slider = QtGui.QSlider(QtCore.Qt.Horizontal, self.playback_slider_group)
        self.playback_slider.setRange(50, 250)
        self.playback_slider.setValue((self.playback_slider.minimum()+self.playback_slider.maximum())/2)
        self.playback_slider_group.layout().addWidget(self.playback_slider)

        control_frame.layout().addWidget(self.play)
        control_frame.layout().addWidget(self.reset)        
        control_frame.layout().addWidget(self.loop)
        control_frame.layout().addWidget(self.quit)                
        control_frame.layout().addWidget(replay_slider_group)        
        control_frame.layout().addWidget(pbar_group)   
        control_frame.layout().addWidget(self.playback_slider_group)
        
        self.timer = QtCore.QTimer(self)
        self.loop_enable = False
        self.on_reset_click()

        ### mapping the messages
        self.connect(self.play, QtCore.SIGNAL('clicked()'), self.on_play_click)
        self.connect(self.reset, QtCore.SIGNAL('clicked()'), self.on_reset_click)
        self.connect(self.loop, QtCore.SIGNAL('clicked()'), self.on_loop_click)
        self.connect(self.replay_slider, QtCore.SIGNAL('valueChanged(int)'), self.on_replay_slider_change)
        self.connect(self.timer, QtCore.SIGNAL('timeout()'), self.on_timeout)
        self.connect(self.playback_slider, QtCore.SIGNAL('valueChanged(int)'), self.on_playback_slider_change)     
        self.connect(self.quit, QtCore.SIGNAL('clicked()'),  QtGui.qApp, QtCore.SLOT('quit()'))

    def on_loop_click(self):
        if self.loop_enable:
            self.loop_enable = False
            self.loop.setText("&Loop")
        else:
            self.loop_enable = True
            self.loop.setText("&Looping")
            if self.paused:
                self.on_play_click()
            
        self.update()
                   
     
    def on_play_click(self):
        if self.paused:
            self.timer.start(100)
            self.play.setText(self.titles['pause'])
            self.paused = False
        else:
            self.timer.stop()
            self.play.setText(self.titles['play'])
            self.paused = True
        self.update()
   

    def on_reset_click(self):
        self.timer.stop()
        self.replay_pbar.reset()
        self.t = 0
        self.r = None
        self.paused = True
        self.replay_finished = False
        self.replay_step = self.replay_slider.value()
        self.playback_slider.setEnabled(False)
        self.playback_slider_group.setEnabled(False)
        self.play.setText(self.titles['play'])
        for s in self.strategies:
            self.pbars[s].setText("Elapsed Time: -- sec\nDownload Progress: 0% ")
            self.pb[s].setText("Playback Rate: --\nBuffering Time: --")
            self.bitmaps[s].chunks = []
            
        for f in self.figures.values():
            f.clear()
            f.xlabel("time (sec)")
            f.ylabel("number useful Chunks")
        self.update()   
    
    def test_all_points(self, points, b, k):
        for (x, y) in points:
            #print "Testing (%.2f, %.2f) b=%.2f, k=%.2f (x-b)*k = %.2f"%(x,y, b,k,(x-b)*k) ,
            if (x-b)*k > y:
                #print "suck! get false"
                return False
            else:
                pass
                #print "cool"
        return True
        
    def on_playback_slider_change(self, r):
        if self.replay_finished:
            k = r*1.0 /256
            for s in self.strategies:
                f = self.figures[s]
                del f.config['data'][1:]
                del f.config['data_pen'][1:]
                
                # Let's binary search the buffer time b:
                points = f.config['data'][0]
                b0 = 0
                b1 = 1200
                
                b = (b0 + b1 ) /2
                
                while b1 - b0 > 10:
                    #print s, len(points), b0, b1
                    sys.stdout.flush()
                    if self.test_all_points(points, b, k):
                        b1 = b
                    else:
                        b0 = b
                    b = (b0 + b1 ) /2
                
                
                f.plot([b, 1200], [0, (1200-b) * k], ':b')
                f.config["figtext"]=[]
                self.pb[s].setText("Playback Rate: %.2fKB/s\nBuffering Time: %.2f sec"%(r, b))
                #f.figtext( 0, -40, "playback_rate = %.2fKB/s"%(r))
                #f.figtext( 0, -20, "buf_time = %.2f sec"%b)
                f.update()
                
        else:
            return    
    
    def on_replay_slider_change(self, r):
        self.replay_step = r
        self.update()
        
    def on_timeout(self):
        if self.replay_finished:
             if self.loop_enable:
                #print "replay finished, let's vary r", self.r
                sys.stdout.flush()
                if self.r is None:
                    self.r = self.playback_slider.minimum()
                    #self.playback_slider.maximum()):
                if self.r < self.playback_slider.maximum():
                    self.on_playback_slider_change(int(self.r))
                    self.playback_slider.setValue(self.r)
                    self.r += 0.5
                    self.update
                elif self.r >= self.playback_slider.maximum():
                    self.timer.stop()
                    self.on_reset_click()
                    self.on_play_click()
             return
        
        
        self.t = self.t + 0.1*self.replay_step
        
        if self.t >= self.replay_pbar.maximum():
            self.t = self.replay_pbar.maximum()
            if not self.loop_enable:
                print "stop timer!"
                sys.stdout.flush()
                self.timer.stop()
            self.replay_finished = True
            self.playback_slider.setEnabled(True)
            self.playback_slider_group.setEnabled(True)
                       
        self.replay_pbar.setValue(math.floor(self.t))
        
        for s in self.strategies:
            f = self.figures[s]
            f.clear()
            
            x_list = []
            y_list = []
            total = 0
            
            for l in self.logs[s]:
                A = l.split(' ')
                t = float(A[0])
                i = int(A[1])
                total = total + 1
                useful = int(A[2])
                if t > self.t:
                    break
                x_list.append(t)
                y_list.append(useful)
                self.bitmaps[s].got_chunk(i)
            
            
            self.logs[s].seek(0)
            if total < 291:
                f.plot(x_list, y_list, "g")
                self.pbars[s].setText("Elapsed Time: %d sec\nDownload Progress: %d%% "%(
                    math.ceil(self.t), total*100/291))
            else:
                f.plot(x_list, y_list, "r")
                self.pbars[s].setText("Elapsed Time: %d sec\nDownload Progress: 100%% "%(
                    math.ceil(self.max_time[s])))
            self.figures[s].xlabel("time (sec)")
            self.figures[s].ylabel("number useful Chunks")
#                self.pbars[s].setText("Downloading Finished %d sec"%(math.ceil(self.max_time[s])))

        sys.stdout.flush()
        self.update()


app = QtGui.QApplication(sys.argv)
mf = MainFrame()
mf.show()
app.exec_()

