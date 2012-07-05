from PyQt4 import QtGui
from PyQt4 import QtCore

class QBitmap(QtGui.QLabel):
    def __init__(self, parent = None, num_chunk = 100):
        QtGui.QLabel.__init__(self, parent)
        self.chunks = []
        self.num_chunk = num_chunk
        self.setFixedHeight(30)

    def got_chunk(self, i):
        self.chunks.append(i)
        self.update()

    def paintEvent(self, event):
        paint = QtGui.QPainter()
        paint.begin(self)
        #paint.setBrush(QtCore.Qt.SolidPattern)
        paint.setBrush(QtCore.Qt.yellow) #QtGui.QColor(223, 135, 19, 255))
        #paint.drawRect(0, 0, self.width(), self.height())
        paint.setPen(QtCore.Qt.black)
        paint.drawRect(0, 0, self.width()-1, self.height()-1)
        
        #brush = QtGui.QBrush(QtCore.Qt.blue, QtCore.Qt.SolidPattern)
        #paint.setBrush(QtCore.Qt.SolidPattern)
        #paint.setPen( QtGui.QPen(QtCore.Qt.blue, 2, QtCore.Qt.SolidLine))
        paint.setPen(QtCore.Qt.blue)
        paint.setBrush(QtCore.Qt.blue)
        intv = (self.width()-1) *1.0 /self.num_chunk 
        j = None
        n = 0
        for i in range(self.num_chunk):
                
            if i in self.chunks:
                if j is not None:
                    n = n + 1
                else:
                    j = i
                    n = 1
            else:
                if j is not None:
                    #paint.setBrush(QtCore.Qt.SolidPattern)
                    paint.drawRect(j*intv, 0, n*intv, self.height()-1)
                    j =  None
                    n =0
        if j is not None:
            paint.drawRect(j*intv, 0, n*intv, self.height()-1)
        
        paint.setBrush(QtCore.Qt.NoBrush)    
        paint.setPen(QtCore.Qt.black)
        paint.drawRect(0, 0, self.width()-1, self.height()-1)
        paint.end()
