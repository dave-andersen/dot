from PyQt4 import QtGui
from PyQt4 import QtCore

class QPlot(QtGui.QFrame):
    def __init__(self, parent = None):
        QtGui.QFrame.__init__(self, parent)
        self.setFrameStyle(QtGui.QFrame.Sunken | QtGui.QFrame.StyledPanel )
        
        self.max_x = 1200
        self.max_y = 291
        self.left_margin = 20
        self.right_margin = 10
        self.top_margin = 10
        self.bottom_margin = 20
        self.w = 250#self.max_x - self.min_x + 1
        self.h = 250 #self.max_y - self.min_y + 1
        
        self.config = {}
        self.clear()
        
        
        self.resize(self.w, self.h)
                
    def xlabel(self, s):
        self.config["xlabel"] = s
        
    def ylabel(self, s):
        self.config["ylabel"] = s
        

    def figtext(self, x, y, s):
        self.config["figtext"].append((x,y,s))
    
    def plot(self, x_list,  y_list = None, s = ""):
        #assert (len(x_list) == len(y_list))
        new_data = []
        for i in range(len(x_list)):
            if y_list is not None:
                new_data.append((x_list[i], y_list[i]))
            else:
                new_data.append((i, x_list[i]))
        self.config["data"].append(new_data)
        if s.find("g") >= 0:
            color = QtCore.Qt.green
        elif s.find("k") >= 0:
            color = QtCore.Qt.black
        elif s.find("r") >= 0:
            color = QtCore.Qt.red
        elif s.find("c") >= 0:
            color = QtCore.Qt.cyan
        elif s.find("m") >= 0:
            color = QtCore.Qt.magenta
        else:
            color = QtCore.Qt.blue # by default
        
        if s.find("--") >= 0:
            style = QtCore.Qt.DashLine
        elif s.find("-.") >= 0:
            style = QtCore.Qt.DashDotLine
        elif s.find(":") >= 0:
            style = QtCore.Qt.DotLine   
        else:
            style = QtCore.Qt.SolidLine    
        
        self.config["data_pen"].append(QtGui.QPen(color, 3, style))
        
    def clear(self):
#        for k in self.config.keys():
#            self.config[k] = 
        self.config["data_pen"] = []
        self.config["data"] = []
        self.config["figtext"] = []
        self.config["xlabel"] = ""
        self.config["ylabel"] = ""
        
    def title(self, title):
        self.config["title"] = title
    
    def paintEvent(self, event):

        paint = QtGui.QPainter()
        self.h = self.height()
        self.w = self.width()
        hh = self.h -1 - self.top_margin - self.bottom_margin
        ww = self.w - 1 - self.left_margin - self.right_margin
        worldmatrix= QtGui.QMatrix(ww*1.0/self.max_x, 0, 0, - hh*1.0/self.max_y,  self.left_margin, self.top_margin + hh)
        
        paint.begin(self)
        
        ### draw axis
        paint.setPen(QtGui.QPen(QtCore.Qt.black, 1, QtCore.Qt.SolidLine))
        
        paint.drawLine(self.left_margin, hh + self.top_margin, \
                       self.left_margin + ww , hh + self.top_margin)
        paint.drawLine(self.left_margin + ww - 8, hh + self.top_margin + 4, \
                       self.left_margin + ww, hh + self.top_margin)  
        paint.drawLine(self.left_margin + ww - 8, hh + self.top_margin - 4, \
                       self.left_margin + ww, hh + self.top_margin)
                       
        paint.drawLine(self.left_margin, hh + self.top_margin, \
                       self.left_margin, self.top_margin)
        paint.drawLine(self.left_margin - 4, self.top_margin + 8, \
                       self.left_margin,  self.top_margin)  
        paint.drawLine(self.left_margin + 4, self.top_margin + 8, \
                       self.left_margin,  self.top_margin) 
        
        ftsize = 15
        paint.font().setPointSize(ftsize)
        
        for (x, y, s) in self.config["figtext"]:
            paint.drawText( 1.0*ww*x/self.max_x + self.left_margin, \
                            self.top_margin +  hh - 1.0 * hh * y / self.max_y, s)
        
        ### draw title
        #paint.drawText(self.max_x/2 - self.min_x - ftsize*len(self.config["title"])/4,  -self.min_y,  self.config["title"])
        paint.setPen(QtGui.QPen(QtCore.Qt.magenta, 2, QtCore.Qt.SolidLine))        
        ### draw x-label
        paint.drawText(self.w / 2 - ftsize*len(self.config["xlabel"])/4,  hh + self.top_margin + 20,  self.config["xlabel"])
        ### draw y-label
        paint.translate(self.left_margin, self.top_margin + hh)
        paint.rotate(-90)
        paint.drawText(hh / 2 - ftsize*len(self.config["ylabel"])/4,  -6,  self.config["ylabel"])
        
        
         
        
        paint.setMatrix(worldmatrix)
        

        
        ### draw curves
        #paint.setPen(s
        for i in range(len(self.config["data"])):
            data_list = self.config["data"][i]
            paint.setPen(self.config["data_pen"][i])  
            #paint.setPen(QtGui.QPen(QtCore.Qt.red, 1, QtCore.Qt.DotLine))

            x_last = None
            y_last = None
            for (xx, yy) in data_list:
                xx = xx 
                if x_last is None:
                    x_last =  xx
                    y_last =  yy
                else:
                    paint.drawLine(x_last,  y_last,  xx,  yy)
                    x_last = xx
                    y_last = yy
                    
        #paint.setPen(QtGui.QPen(QtCore.Qt.magenta, 2, QtCore.Qt.SolidLine))
        #paint.font().setPointSize(15)
        
        paint.end()

