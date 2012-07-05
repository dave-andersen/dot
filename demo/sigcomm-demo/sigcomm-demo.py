#!/usr/bin/python

# Imports and inits Soya.

import sys, os, os.path, random, time, new
from optparse import OptionParser
import soya, soya.sphere, soya.cube
import soya.pudding as pudding
import soya.pudding.ext.meter, soya.label3d
import soya.gui

#everytime GRANULARITY seconds of real time elapses,
# advance demo clock by SPEEDUP
GRANULARITY = 0.1
SPEEDUP = 0.1
NUMNODES = 15 #including seed
DOT = 'SET' #which dot, set or dsync
SEEDNUMS = [9, 14]
WINDOWS = []
LEGEND = [(0.0, 0.0, 1, 1.0), (0.45, 0.63, 0.78, 1.0), (0.79, 0.54, 0.55, 0.8), (1.0, 0.0, 0.0, 0.7)]
#(0.74, 0.85, 0.96, 1.0) (0.9, 0.8, 0.8, 1.0)
MATERIAL = []

class TimeLabel(soya.gui.Label):
    def __init__(self, parent=None, sim=None):
        text = u"".join("Time Elapsed:  %.3f" % 000.0)
        soya.gui.Label.__init__(self, parent, text, (1.0, 1.0, 1.0, 1.0))
        self.parent = parent
        self.sim = sim

    def begin_round(self):
        if self.sim.done < 1:
            self._text = u"".join("Time Elapsed:  %.1f" % self.sim.elapsed)
            self._changed = -2
        else:
            self.color = (1, 0.2, 0.2, 1)
  
class DoneMeter(soya.gui.ProgressBar):
    global DOT
    def __init__(self, parent=None, root=None, tool=None, adj=0):
        self.name = tool
        if tool == 'DOT':
            self.name = DOT
        self.tool = tool
        self.root = root
        self.adj = adj

        text = "%s Progress" % self.name
        self.label = soya.gui.Label(parent, text, (1.0, 1.0, 1.0, 1.0))
        
        soya.gui.ProgressBar.__init__(self, parent, 0)

        text = u"".join(" %3d%%" % 100)
        self.label2 = soya.gui.Label(parent, text, self.root.tools[tool]['color'])

    def begin_round(self):
        pct = self.root.tools[self.tool]['pct']
        self.value = pct/100
        self.label2._text = u"".join(" %3d%%" % pct)
        self.label2._changed = -2
        
    def update_label(self, tool=None):
        self.name = tool
        if tool == 'DOT':
            self.name = DOT
        self.tool = tool

        #print DOT, self.name

        text = "%s Progress" % self.name
        self.label._text = text
        self.label._changed = -2

class MoveableCamera(soya.Camera):
    def __init__(self, parent):
        soya.Camera.__init__(self, parent)
        self.fov = 10
        self.speed = soya.Vector(self)
        self.x_rotate_speed = 0.0
        self.y_rotate_speed = 0.0
        self.x_speed = 0.0
        self.z_speed = 0.0
        self.impact = None
        self.default_x = self.x = 0.0
        self.default_y = self.y = 20.0
        self.default_z = self.z = -25.0

    def begin_round(self):
        soya.Camera.begin_round(self)
                    
    def advance_time(self, proportion):
        soya.Camera.advance_time(self, proportion)

        self.add_mul_vector(proportion, self.speed)
        self.turn_x(self.x_rotate_speed * proportion)
        self.turn_y(self.y_rotate_speed * proportion)
        self.x += proportion * self.x_speed
        self.z += proportion * self.z_speed

####################
# Create the objects
####################

model_builder = soya.SimpleModelBuilder()
model_builder.shadow = 1

black = soya.Material(); black   .diffuse = (0.0, 0.0, 0.0, 1.0)
red   = soya.Material(); red     .diffuse = (1.0, 0.0, 0.0, 1.0)
gray  = soya.Material(); gray    .diffuse = (0.5, 0.5, 0.5, 1.0)
green = soya.Material(); green   .diffuse = (0.0, 1.0, 0.0, 1.0)
blue  = soya.Material(); blue    .diffuse = (0.0, 0.0, 1.0, 1.0)
hl    = soya.Material(); hl      .diffuse = (0.6, 0.6, 0.0, 1.0)
yellow    = soya.Material(); yellow      .diffuse = (1.0, 1.0, 0.0, 1.0)
pink    = soya.Material(); pink      .diffuse = (1.0, 0.0, 1.0, 1.0)

nw  = soya.sphere.Sphere(None, red);  nw.model_builder  = model_builder
nw1  = soya.sphere.Sphere(None, yellow);  nw1.model_builder  = model_builder

nwd = soya.sphere.Sphere(None, green); nwd.model_builder = model_builder

nws = soya.sphere.Sphere(None, blue); nws.model_builder = model_builder
nws1 = soya.sphere.Sphere(None, gray);  nws1.model_builder = model_builder

node_model = []
node_model.append(nw.to_model())
node_model.append( nw1.to_model())

node_done_model = nwd.to_model()

node_seed_model = []
node_seed_model.append(nws.to_model())
node_seed_model.append(nws1.to_model())

hl_model        = soya.cube.Cube(None, hl).to_model()
disk_model      = soya.cube.Cube(None, green).to_model()
chunk_model     = soya.cube.Cube(None, blue).to_model()

class NodeWorld(soya.World):
    global DOT, MATERIAL

    def __init__(self, parent, num, name, xpos, zpos, model, sim=None):
        soya.World.__init__(self, parent)
        
        self.sim = sim

        self.body = soya.Body(self, model)

        self.scale(0.1, 0.1, 0.1)
        self.x = xpos
        self.z = zpos
        #print "name ", name, " x ", self.x, " z ", self.z
        self.name = name
        self.num = num

        # incoming chunks
        self.chunks = []
        self.total_chunks = 0
        self.xput = []
        self.perc = []

        # add label
        self.label = soya.label3d.Label3D(self, self.name)
        self.label.set_xyz(0.0, 3.0, 0.0)
        self.label.size = 0.06
        self.label.lit = 0

        self.done = False
        self.pct = 0

    def update_label(self):
        if self.total_chunks > 0:
            try:
                pct = 100 - (100.0 * len(self.chunks) / self.total_chunks)
            except ZeroDivisionError:
                pct = 100
        else:
            pct = self.pct
        
        self.label.text = "%s (%d%%) " % (self.name, pct)
                        
    def remove_connections(self):
        while 1:
            working = 0
            for i in range(1, len(self.children)):
                if isinstance(self.children[i], soya.World):
                    self.remove(self.children[i])
                    working = 1
                    break
            if working == 0:
                break

    def get_color_index(self, xput):
        if xput < 50: return(0)
        elif xput < 250: return(1)
        elif xput < 1000: return(2)
        else: return(3)

    def get_width(self, xput):
        xput = xput/100
        xput = xput* 0.25;
        if xput > 2.0:
            xput = 2.0
        return (xput)

    def update_connections(self, xput):
        self.remove_connections()
        xarr = xput.split(',')
        for i in range(len(xarr)):
            #print "zrr ", i, " ", xarr[i]
            if float(xarr[i]) <= 0:
                continue
            pt1 = soya.Vertex(self, 0, 0, 0)
            pt2 = soya.Vertex(self.sim.nodes[i], 0, 0, 0)
            color = self.get_color_index(float(xarr[i]))
            width = self.get_width(float(xarr[i])) 
            c = soya.cube.Cube(self, MATERIAL[color])
            c.scale(width, 0.05, pt1.distance_to(pt2))
            c.look_at(self.sim.nodes[i])
            v = c.vector_to(self.sim.nodes[i])
            v = v / 2
            v.y -= 0.5
            c.move(v)

    def begin_round(self):
        soya.World.begin_round(self)

        t = self.sim.parsim.elapsed
        while len(self.chunks) > 0:
            c = self.chunks.pop(0)
            if t >= c[0]:
                continue
                #print "t=%f, c[0]=%f" % (t, c[0])
                #if self.num == self.sim.current_dst:
                #    if c[1] < 0:
                #        if DOT == 'dsync':
                #            self.sim.send_disk_chunk()
                #        else:
                #            continue
                #    else:
                #        self.sim.send_net_chunk(c[1])
                #else:
                #    continue
            elif t < c[0]:
                self.chunks.insert(0, c)
                break

        cur_xput = ''    
        while len(self.xput) > 0:
            x = self.xput.pop(0)
            if t >= x[0]:
                cur_xput = x[1]
            elif t < x[0]:
                self.xput.insert(0, x)
                break

        if cur_xput != '' and (self.sim.current_dst == -1 or self.num == self.sim.current_dst):
            self.update_connections(cur_xput)

        self.update_label()

        while len(self.perc) > 0:
            p = self.perc.pop(0)
            if t >= p[0]:
                self.pct = p[1]
            elif t < p[0]:
                self.perc.insert(0, p)
                break
                 
        if not isinstance(self, Seed):
            if (self.total_chunks > 0 and not self.done and len(self.chunks) == 0) or (self.pct >= 100 and not self.done): #SET or BT
                self.done = True
                self.body.set_model(node_done_model)
                self.sim.nodes_not_done -= 1
                if self.sim.nodes_not_done <= 0:
                    self.sim.parsim.done += 1
            
class Seed(NodeWorld):
    def update_label(self):
        self.label.text = self.name

class DiskWorld(soya.World):
    def __init__(self, parent, near_node):
        soya.World.__init__(self, parent)

        self.body = soya.Body(self, disk_model)

        self.scale(0.2, 0.4, 0.2)
        self.x = near_node.x + 0.5
        self.z = near_node.z - 0.5

        # add label
        self.label = soya.label3d.Label3D(self, "Disk")
        self.label.set_xyz(0.0, -1.5, 0.0)
        self.label.size = 0.03
        self.label.lit = 0

    def relocate(self, near_node):
        self.x = near_node.x + 0.5
        self.z = near_node.z - 0.5

class ChunkWorld(soya.World):
    def __init__(self, parent, src, dst, sim=None):
        soya.World.__init__(self, parent)

        self.sim = sim
        
        self.speed = soya.Vector(self, 0.0, 0.0, 0.0)
        self.src = src
        self.dst = dst

        self.body = soya.Body(self, chunk_model)

        self.scale(0.08, 0.08, 0.08)
        self.x = src.x
        self.z = src.z

        v = self.vector_to(dst)
        v.normalize()
        self.speed = v * 0.05

    def remove(self):
        self.parent.remove(self)
        self.sim.chunks_in_flight.remove(self)

    def begin_round(self):
        soya.World.begin_round(self)

    def advance_time(self, proportion):
        soya.World.advance_time(self, proportion)
        
        if self.distance_to(self.dst) < 0.1:
            self.remove()

        if self.sim.parsim.paused:
            return

        self.add_mul_vector(proportion, self.speed)

class Simulation(soya.Volume):
    def __init__(self, scene, parsim, datadir):
        soya.Volume.__init__(self, scene, soya.Shape())
        self.scene = scene
        self.parsim = parsim
        self.datadir = datadir

        global NUMNODES, SEEDNUMS

        self.nodes = []
        self.chunks_in_flight = []

        # TRACE data
        for i in range(NUMNODES):
            l = []
            xput = []
            n = []
            p = []

            try:
                fname = "%s/%d.log" % (self.datadir, i)
                fsock = open(fname, "r")
                try:
                    line = fsock.next();
                    parts = line.rstrip().split() 
                    #(index, color, x, z, n) = line.rstrip().split()
                    #print i, parts

                    #assign values
                    index = parts.pop(0)
                    color = int(parts.pop(0))
                    x = parts.pop(0)
                    z = parts.pop(0)
                    name = ' '.join(parts)

                    for line in fsock:
                        #print line
                        (id, t, s) = line.rstrip().split()
                        #print "node ", i, "id", id, " t ", t, " s ", s
                        if id == 'XPUT':
                            xput.append((float(t), s))
                        elif id == 'PERC':
                            p.append((float(t), float(s)))
                        else:
                            l.append((float(t), int(s)))
                finally:
                    fsock.close()

                try:
                    spos = SEEDNUMS.index(i)
                except ValueError:
                    spos = -1

                if spos != -1:
                    node = Seed(self.scene, num=i, name=name, xpos=float(x), zpos=float(z), model=node_seed_model[color], sim=self)
                else:
                    node = NodeWorld(self.scene, num=i, name=name, xpos=float(x), zpos=float(z), model=node_model[color], sim=self)

                self.nodes.append(node)
                node.chunks.extend(l)
                node.xput.extend(xput)
                node.total_chunks = len(l)
                node.perc.extend(p)
            except IOError, e:
                print e

        self.nodes_not_done = len(self.nodes) - len(SEEDNUMS)
        global DOT
        if DOT == 'dsync':
            self.nodes_not_done -= 1 #for ucb dsl
        self.current_dst = -1
        #if DOT == 'dsync':
        #    self.disk = DiskWorld(self.scene, self.nodes[self.current_dst])
        self.clicked_node()

    def send_net_chunk(self, src=None):
        if not src:
            src = random.randint(0, len(self.nodes)-1)
            while src == self.current_dst:
                src = random.randint(0, len(self.nodes)-1)
        c = ChunkWorld(self.scene, self.nodes[src], self.nodes[self.current_dst], sim=self)
        self.chunks_in_flight.append(c)

    def send_disk_chunk(self):
        c = ChunkWorld(self.scene, self.disk, self.nodes[self.current_dst], sim=self)
        self.chunks_in_flight.append(c)

    def clicked_node(self, node=None):
        
        # removing the square under the node
        if self.current_dst != -1:
            #for i in range(1, len(self.nodes[self.current_dst].children)):
            #    if isinstance(self.nodes[self.current_dst].children[i], soya.Body):
            #        self.nodes[self.current_dst].remove(self.nodes[self.current_dst].children[i])
            #        break
                
            # removing the lines from the node    
            self.nodes[self.current_dst].remove_connections()
        else:
            for i in range(0, len(self.nodes)):
                self.nodes[i].remove_connections()
        
        if not node:
            self.current_dst = -1
        else:
            self.current_dst = node.num
            #if DOT == 'dsync':
            #    self.disk.relocate(node)

            # draw square under the current node
            #b = soya.Body(self.nodes[self.current_dst], hl_model)
            #b.scale(4, 0.01, 4)
            #b.y -= 1.0

        # remove current in-flight chunks
        while len(self.chunks_in_flight) > 0:
            self.chunks_in_flight[0].remove()

class MyDemo():
    def __init__(self, root=None, scheme=u"SET", datadir=None):
        self.root = root
        self.scheme = scheme
        self.datadir = datadir
    
        # Creates the scene.
        self.scene = soya.World()
        
        # the simulation holds the demo state
        self.sim = Simulation(self.scene, root.sim, self.datadir)

        self.window = MyDemoWindow(self.root, parptr=self)
        self.layer = soya.gui.Layer(self.window)
        self.time_l = soya.gui.VList(self.layer, 1)
        self.time_l.value = -1

        # Creates a light.
        self.light = soya.Light(self.scene)
        self.light.set_xyz(0.0, 8.0, 0.0)

        # Creates a camera
        self.camera = MoveableCamera(self.scene)
        self.camera.look_at(soya.Point(self.scene, 0,0,0))
        self.camera.partial = 1

        self.cv = soya.gui.CameraViewport(self.layer)
        self.cv.ideal_width = 1024
        self.cv.ideal_height = 550
        self.cv.set_camera(self.camera)
        
        if self.scheme == u"SET" or self.scheme == u"dsync":
            self.window.move(1600-1024-20, 0)
        else:
            self.window.move(1600-1024-20, 600)
        
        title = soya.gui.Label(self.layer, self.scheme, (1.0, 0.0, 1.0, 1.0))
        title.begin_round = new.instancemethod(lambda self: self.move(self.parent.x+self.parent.width/2, self.parent.y+20), title, title.__class__)
        
        soya.MAIN_LOOP.scenes.append(self.scene)
       
        
class MyDemoWindow(soya.gui.Window):
    def __init__(self, root = None, parptr = None, closable = 0):
        #soya.gui.Window.__init__(self, root, parptr.scheme, closable)
        soya.gui.Window.__init__(self, root, u"", closable)
        self.parptr = parptr
        global WINDOWS
        WINDOWS.append(self)

#################
# SETUP
#################
class MySim(soya.Volume):
    def __init__(self, root=None):
        self.scene = soya.World()
        soya.Volume.__init__(self, self.scene, soya.Shape())
        self.root = root
        self.elapsed = 0
        self.ticks = 0.0
        self.paused = True
        self.done = 0
        
        global SPEEDUP, GRANULARITY

        self.dot_log = []
        self.bt_log = []
        
        #read DOT log
        try:
            fname = "%s%s" % (root.dot_dir, "/dot.log")
            fsock = open(fname, "r")
            try:
                for line in fsock:
                    (t, p) = line.rstrip().split()
                    self.dot_log.append((float(p)))
            finally:
                fsock.close()
        except IOError, e:
            print e

        #read bittorrent log
        try:
            fname = "%s%s" % (root.bt_dir, "/bt.log") 
            fsock = open(fname, "r")
            try:
                for line in fsock:
                    (t, p) = line.rstrip().split()
                    self.bt_log.append((float(p)))
            finally:
                fsock.close()
        except IOError, e:
            print e
        
        soya.MAIN_LOOP.scenes.append(self.scene)
            
    def begin_round(self):
        int_time = int(self.elapsed)
        if int_time < len(self.dot_log):
            self.root.tools['DOT']['pct'] = self.dot_log[int_time]
        else:
            self.root.tools['DOT']['pct'] = 100
            
        if int_time < len(self.bt_log):
            self.root.tools['BitTorrent']['pct'] = self.bt_log[int_time]
            self.root.tools['rsync']['pct'] = self.bt_log[int_time]
        else:
            self.root.tools['BitTorrent']['pct'] = 100
            self.root.tools['rsync']['pct'] = 100
            
    def advance_time(self, proportion):
        if self.paused or self.done >= 1:
            return
        
        #print soya.MAIN_LOOP.round_duration, proportion
        self.ticks += 1.0 * proportion
        if self.ticks > GRANULARITY / soya.MAIN_LOOP.round_duration:
            self.ticks = 0.0
            self.elapsed += SPEEDUP


class MyRootLayer(soya.gui.RootLayer):
    def __init__(self, parent=None):
        soya.gui.RootLayer.__init__(self, None)
        self.sim = None

    def on_key_pressed(self, key, mods):
        global SPEEDUP, GRANULARITY

        if key == soya.sdlconst.K_q:      soya.MAIN_LOOP.stop(Demo.STATE_END)
        elif key == soya.sdlconst.K_r or key == soya.sdlconst.K_s:     #swtich to dsync vs rsync
            while len(WINDOWS) > 0:
                w = WINDOWS.pop(0)
                w.close()
            if key == soya.sdlconst.K_s:
                soya.MAIN_LOOP.stop(Demo.STATE_DSYNC)
            else:
                soya.MAIN_LOOP.stop(Demo.STATE_MAIN)
        elif key == soya.sdlconst.K_f:
            SPEEDUP = SPEEDUP*10;
        elif key == soya.sdlconst.K_b:
            SPEEDUP = SPEEDUP/10;
            if SPEEDUP < 0.01:
                SPEEDUP = 0.01
        else:
            for i in range(0, len(WINDOWS)):
                w = WINDOWS[i]
                if   key == soya.sdlconst.K_UP:     w.parptr.camera.speed.z = -0.5
                elif key == soya.sdlconst.K_DOWN:   w.parptr.camera.speed.z =  0.5
                elif key == soya.sdlconst.K_l:      w.parptr.camera.x_speed =  0.5
                elif key == soya.sdlconst.K_h:      w.parptr.camera.x_speed = -0.5
                elif key == soya.sdlconst.K_j:      w.parptr.camera.z_speed =  0.5
                elif key == soya.sdlconst.K_k:      w.parptr.camera.z_speed = -0.5
                elif key == soya.sdlconst.K_7:
                    for i in range(0, len(w.parptr.sim.nodes)):
                        if w.parptr.sim.nodes[i].num == 7:               
                            w.parptr.sim.clicked_node(w.parptr.sim.nodes[i])
                elif key == soya.sdlconst.K_a:
                    w.parptr.sim.clicked_node(None)


    def on_key_released(self, key, mods):
        if key == soya.sdlconst.K_p:               self.sim.paused = not self.sim.paused
        else:
            for i in range(0, len(WINDOWS)):
                w = WINDOWS[i]
                if   key == soya.sdlconst.K_UP:     w.parptr.camera.speed.z = 0.0
                elif key == soya.sdlconst.K_DOWN:   w.parptr.camera.speed.z = 0.0
                elif key == soya.sdlconst.K_h:      w.parptr.camera.x_speed = 0.0
                elif key == soya.sdlconst.K_l:      w.parptr.camera.x_speed = 0.0
                elif key == soya.sdlconst.K_j:      w.parptr.camera.z_speed = 0.0
                elif key == soya.sdlconst.K_k:      w.parptr.camera.z_speed = 0.0

class MyMenu(soya.gui.Window):
    def __init__(self, root = None, scheme = u"", x = 0, y = 0, closable = 0):
        soya.gui.Window.__init__(self, root, scheme, closable)
        self.x = x
        self.y = y
        self.title = scheme
        
    def begin_round(self):
        soya.gui.Window.begin_round(self)
        self.move(self.x, self.y)

class Demo:
    STATE_MAIN = 0
    STATE_END = 1
    STATE_DSYNC = 2

    title = "DOT Demo"
    global WINDOWS, LEGEND, MATERIAL, DOT

    def __init__(self, datafile=None, fullscreen=False):
        soya.init(width=1600, height=1200, title=Demo.title, \
                  resizeable=True, fullscreen=fullscreen)
        
        self.state = Demo.STATE_MAIN

    def start(self):
        #create MATERIALS from LEGENDS
        for i in range(0, len(LEGEND)):
            m = soya.Material(); m  .diffuse = LEGEND[i]
            MATERIAL.append(m)

        root  = MyRootLayer()
        backg = soya.gui.Image(root, black)

        root.tools = {
            'DOT'     : { 'color' : (0, 1, 0, 1),
                            'pct' : 0
                          },
            'BitTorrent'       : { 'color' : (0, 1, 0, 1),
                            'pct' : 0
                          },
            'rsync'     : { 'color' : (1, 0, 0, 1),
                            'pct' : 0
                          }
        }
        
        root.dot_dir = "raw/data-set-parse"
        root.bt_dir = "raw/data-bt-parse"
        
        statw = MyMenu(root, u"Statistics", 10, 10, closable=0)
        stat_layer = soya.gui.Layer(statw)
        stat_backg = soya.gui.Image(stat_layer, black)
        table = soya.gui.VTable(stat_layer, 1)
        table.row_pad = table.col_pad = 40

        stat_l = soya.gui.VList(table, 3)
        stat_l.value = -1
        dot_done_meter = DoneMeter(stat_l, root=root, tool='DOT', adj=3)
        bt_done_meter = DoneMeter(stat_l, root=root, tool='BitTorrent', adj=2)

        time_l = soya.gui.VList(table)
        time_l.value = -1
        time_label = TimeLabel(time_l)

        #make the legend
        #soya.gui.Label(table, u"Throughput Legend", (1.0, 1.0, 1.0, 1.0))
        l = soya.gui.VList(table)
        l.value = -1
        soya.gui.Label(l, u"Throughput Legend", (1.0, 1.0, 1.0, 1.0))
        soya.gui.Label(l, u" < 50 Kbps", LEGEND[0])
        soya.gui.Label(l, u"50-250 Kbps", LEGEND[1])
        soya.gui.Label(l, u"250-1000 Kbps", LEGEND[2])
        soya.gui.Label(l, u" > 1 Mbps", LEGEND[3])
                
                
        soya.set_root_widget(root)
        global SPEEDUP, DOT
        while (self.state != None and self.state != Demo.STATE_END):
            idler = soya.MainLoop()
            
            if self.state == Demo.STATE_MAIN:
                root.dot_dir = "raw/data-set-parse"
                root.bt_dir = "raw/data-bt-parse"
            else:
                root.dot_dir = "raw/data-dsync-parse"
                root.bt_dir = "raw/data-rsync-parse"
            
            root.sim = MySim(root)
            
            if self.state == Demo.STATE_MAIN:
                DOT = 'SET'
                MyDemo(root, u"SET", root.dot_dir)
                MyDemo(root, u"BitTorrent", root.bt_dir)
                dot_done_meter.update_label(tool='DOT')
                bt_done_meter.update_label(tool='BitTorrent')
            else:
                DOT = 'dsync'
                #print DOT
                MyDemo(root, u"dsync", root.dot_dir)
                MyDemo(root, u"rsync", root.bt_dir)
                dot_done_meter.update_label(tool='DOT')
                bt_done_meter.update_label(tool='rsync')
                
            
            time_label.sim = root.sim
            time_label.color = (1.0, 1.0, 1.0, 1.0)
            SPEEDUP = 0.01

            self.state = idler.idle()
            
if __name__ == "__main__":
    usage = "%prog [options] data_file"
    parser = OptionParser(usage)
    parser.add_option("-f", "--fullscreen",
                      action="store_true", dest="fullscreen", default=False,
                      help="run in fullscreen mode")
    opts, args = parser.parse_args()

    if len(args) != 1:
        parser.error("incorrect number of arguments")

    demo = Demo(datafile=args[0], fullscreen=opts.fullscreen)
    demo.start()
    
    
