#!/usr/bin/python

# Imports and inits Soya.

import sys, os, os.path, random, time
from optparse import OptionParser
import soya, soya.sphere, soya.cube
import soya.pudding as pudding
import soya.pudding.ext.meter, soya.label3d

GRANULARITY = 0.01
SPEEDUP = 5000.0

class TimeLabel(pudding.control.SimpleLabel):
    def __init__(self, parent=None, sim=None, margin=20, font=None):
        pudding.control.SimpleLabel.__init__(self, parent, font=font, autosize=True)

        self.sim = sim

        self.right = margin
        self.bottom = margin
        self.anchors = pudding.ANCHOR_BOTTOM_RIGHT

    def begin_round(self):
        if self.sim.nodes_not_done > 0:
            self.label = "Time Elapsed:  %.1f" % self.sim.elapsed
        else:
            self.color = (1, 0.2, 0.2, 1)
        self.update()
        self.on_resize()

class DoneMeter(pudding.ext.meter.MeterLabel):
    def __init__(self, parent=None, sim=None, font=None, tool=None):
        pudding.ext.meter.MeterLabel.__init__(self, parent)

        self.sim = sim
        self.name = tool

        self.height = 50

        self.meter.border_color = (1, 1, 1, 1)
        self.meter.color = self.sim.tools[tool]['color']
        self.meter.user_change = False
        self.meter.value = 0

        self.label.color = self.meter.border_color
        self.label.font = font
        self.label.set_pos_bottom_right(5)

        self.label.autosize = False
        self.label.width = 325
        self.label.label = "%s Progress" % self.name

        self.set_child_options(self.meter, flags=pudding.CENTER_VERT)

        self.label2 = pudding.control.SimpleLabel()
        self.label2.color = (1, 1, 1, 1)
        self.label2.font = font
        self.add_child(self.label2, pudding.ALIGN_RIGHT)

    def begin_round(self):
        #pct = 100.0 * self.sim.arrived_chunks / self.sim.total_chunks
        pct = self.sim.tools[self.name]['pct']
        self.meter.value = pct
        self.label2.label = " %3d%%" % pct

        self.update()
        self.on_resize()

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
        self.default_y = self.y = 30.0
        self.default_z = self.z = -30.0

    def begin_round(self):
        soya.Camera.begin_round(self)
            
        for event in soya.MAIN_LOOP.events:
            if event[0] == soya.sdlconst.KEYDOWN:
                if   event[1] == soya.sdlconst.K_UP:     self.speed.z = -0.5
                elif event[1] == soya.sdlconst.K_DOWN:   self.speed.z =  0.5
                #elif event[1] == soya.sdlconst.K_LEFT:   self.y_rotate_speed = -2.0
                #elif event[1] == soya.sdlconst.K_RIGHT:  self.y_rotate_speed =  2.0
                elif event[1] == soya.sdlconst.K_l:      self.x_speed =  0.5
                elif event[1] == soya.sdlconst.K_h:      self.x_speed = -0.5
                elif event[1] == soya.sdlconst.K_j:      self.z_speed =  0.5
                elif event[1] == soya.sdlconst.K_k:      self.z_speed = -0.5
                elif event[1] == soya.sdlconst.K_r:      soya.MAIN_LOOP.stop(Demo.STATE_MAIN)
                elif event[1] == soya.sdlconst.K_q:      soya.MAIN_LOOP.stop(Demo.STATE_END)
                elif event[1] == soya.sdlconst.K_ESCAPE: soya.MAIN_LOOP.stop(Demo.STATE_END)
                elif event[1] == soya.sdlconst.K_RETURN:
                    self.set_xyz(self.default_x, self.default_y, self.default_z)
                elif event[1] == soya.sdlconst.K_f:
                    global SPEEDUP, GRANULARITY
                    if SPEEDUP == 5:
                        SPEEDUP = 1; GRANULARITY = 0.01
                    else:
                        SPEEDUP = 5; GRANULARITY = 0.1
                #elif event[1] == soya.sdlconst.K_SPACE:  self.look_at(soya.Point(self.parent, 0,0,0))
            if event[0] == soya.sdlconst.KEYUP:
                if   event[1] == soya.sdlconst.K_UP:     self.speed.z = 0.0
                elif event[1] == soya.sdlconst.K_DOWN:   self.speed.z = 0.0
                #elif event[1] == soya.sdlconst.K_LEFT:   self.y_rotate_speed = 0.0
                #elif event[1] == soya.sdlconst.K_RIGHT:  self.y_rotate_speed = 0.0
                elif event[1] == soya.sdlconst.K_h:      self.x_speed = 0.0
                elif event[1] == soya.sdlconst.K_l:      self.x_speed = 0.0
                elif event[1] == soya.sdlconst.K_j:      self.z_speed = 0.0
                elif event[1] == soya.sdlconst.K_k:      self.z_speed = 0.0
                elif event[1] == soya.sdlconst.K_s:
                    soya.screenshot().resize((1024, 768)).save("screenshot.jpg")

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

red   = soya.Material(); red     .diffuse = (1.0, 0.0, 0.0, 1.0)
gray  = soya.Material(); gray    .diffuse = (0.2, 0.2, 0.2, 1.0)
green = soya.Material(); green   .diffuse = (0.0, 1.0, 0.0, 1.0)
blue  = soya.Material(); blue    .diffuse = (0.0, 0.0, 1.0, 1.0)
hl    = soya.Material(); hl      .diffuse = (0.6, 0.6, 0.0, 1.0)

nw  = soya.sphere.Sphere(None, red);  nw.model_builder  = model_builder
nwd = soya.sphere.Sphere(None, gray); nwd.model_builder = model_builder
nws = soya.sphere.Sphere(None, blue); nws.model_builder = model_builder
node_model      = nw.to_model()
node_done_model = nwd.to_model()
node_seed_model = nws.to_model()
#hl_model        = soya.sphere.Sphere(None, hl).to_model()
hl_model        = soya.cube.Cube(None, hl).to_model()
disk_model      = soya.cube.Cube(None, green).to_model()
chunk_model     = soya.cube.Cube(None, blue).to_model()

class NodeWorld(soya.World):
    def __init__(self, parent, num, name, xpos, zpos, sim=None):
        soya.World.__init__(self, parent)
        
        self.sim = sim

        self.body = soya.Body(self, node_model)

        self.scale(0.1, 0.1, 0.1)
        self.x = xpos
        self.z = zpos
        #print "name ", name, " x ", self.x, " z ", self.z
        self.name = name
        self.num = num

        # incoming chunks
        self.chunks = []
        self.total_chunks = 0

        # add label
        self.label = soya.label3d.Label3D(self, self.name)
        self.label.set_xyz(0.0, 3.0, 0.0)
        self.label.size = 0.06
        self.label.lit = 0

        self.done = False

    def update_label(self):
        try:
            pct = 100 - (100.0 * len(self.chunks) / self.total_chunks)
        except ZeroDivisionError:
            pct = 100
        self.label.text = "%s (%d%%) " % (self.name, pct)
        #self.label.look_at(camera)

    def begin_round(self):
        soya.World.begin_round(self)

        t = self.sim.elapsed
        while len(self.chunks) > 0:
            c = self.chunks.pop(0)
            self.sim.arrived_chunks += 1
            if t >= c[0]:
                #print "t=%f, c[0]=%f" % (t, c[0])
                if self.num == self.sim.current_dst:
                    if c[1] < 0:
                        self.sim.send_disk_chunk()
                    else:
                        self.sim.send_net_chunk(c[1])
                else:
                    continue
            elif t < c[0]:
                self.chunks.insert(0, c)
                self.sim.arrived_chunks -= 1
                break

        self.update_label()

        if isinstance(self, Seed):
            self.body.set_model(node_seed_model)
        elif not self.done and len(self.chunks) == 0: # \
           #and (self.num != current_dst or len(self.sim.chunks_in_flight) == 0):
            self.done = True
            self.body.set_model(node_done_model)
            self.sim.nodes_not_done -= 1

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

        #self.speed = soya.Vector(self, 0.0, 0.0, -0.2)
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

        #print self.distance_to(self.dst)
        if self.distance_to(self.dst) < 0.1:
            self.remove()

        if self.sim.paused:
            return

        self.add_mul_vector(proportion, self.speed)

class Simulation(soya.Volume):
    def __init__(self, scene):
        soya.Volume.__init__(self, scene, soya.Shape())
        self.scene = scene

        self.elapsed = 0
        self.ticks = 0.0
        self.paused = True

        global SPEEDUP, GRANULARITY
        SPEEDUP = 1.0
        GRANULARITY = 0.01

        self.tools = {
            'dsync'     : { 'color' : (1, 0, 0, 1),
                            'pct' : 0
                          },
            'SET'       : { 'color' : (0, 1, 0, 1),
                            'pct' : 0
                          },
            'rsync'     : { 'color' : (0, 0, 1, 1),
                            'pct' : 0
                          }
        }

        self.nodes = []
        self.chunks_in_flight = []

        self.total_chunks = 0
        self.arrived_chunks = 0

        self.set_log = []
        self.rsync_log = []

        ### Load data (time, source); source < 0 means from disk

        # RANDOM data for testing
#        for i in range(2):
#            node = NodeWorld(self.scene, i, sim=self)
#            self.nodes.append(node)
#            n = random.randint(100, 700)
#            l = []
#            for j in range(n):
#                t = random.randint(0, random.randint(2, 15))
#                s = random.randint(-1, len(self.nodes)-1)
#                print "node ", i, " t ", t, " s ", s
#                if (s != i): l.append((t, s))
#            l.sort(cmp=lambda x, y: cmp(x[0], y[0]))
#             #print i, l
#            node.chunks.extend(l)
#            node.total_chunks = len(l)
#            self.total_chunks += node.total_chunks

        # TRACE data
        for i in range(10):
            l = []
            try:
                fname = "data-dsync/%d.log" % i
                fsock = open(fname, "r")
                try:
                    line = fsock.next();
                    (x, z, name) = line.rstrip().split()
                    for line in fsock:
                        (id, t, s) = line.rstrip().split()
                        #print "node ", i, "id", id, " t ", t, " s ", s
                        l.append((float(t), int(s)))
                finally:
                    fsock.close()

                #print "x ", x, " z ", z, " n ", name
                node = NodeWorld(self.scene, num=i, name=name, xpos=float(x), zpos=float(z), sim=self)
                self.nodes.append(node)
                node.chunks.extend(l)
                node.total_chunks = len(l)
                self.total_chunks += node.total_chunks
            except IOError, e:
                print e

        #read set log
        try:
            fname = "data-dsync/set.log" 
            fsock = open(fname, "r")
            try:
                for line in fsock:
                    (t, p) = line.rstrip().split()
                    self.set_log.append((float(p)))
            finally:
                fsock.close()
        except IOError, e:
            print e
        
        #copy+paste for now    
        #read rsync log
        try:
            fname = "data-dsync/rsync.log" 
            fsock = open(fname, "r")
            try:
                for line in fsock:
                    (t, p) = line.rstrip().split()
                    self.rsync_log.append((float(p)))
            finally:
                fsock.close()
        except IOError, e:
            print e
              
        self.nodes_not_done = len(self.nodes)
        self.current_dst = 7

        # Sender is the last node
        node = Seed(self.scene, num=i, name="Seed", xpos=0, zpos=0, sim=self)
        self.nodes.append(node)

        self.disk = DiskWorld(self.scene, self.nodes[self.current_dst])
        self.clicked_node(self.nodes[self.current_dst])

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

    def clicked_node(self, node):
        if isinstance(self.nodes[self.current_dst].children[-1], soya.Body):
            self.nodes[self.current_dst].remove(self.nodes[self.current_dst].children[-1])

        self.current_dst = node.num
        self.disk.relocate(node)

        # draw square under the current node
        b = soya.Body(self.nodes[self.current_dst], hl_model)
        b.scale(4, 0.01, 4)
        b.y -= 1.0

        # remove current in-flight chunks
        while len(self.chunks_in_flight) > 0:
            self.chunks_in_flight[0].remove()

    def begin_round(self):
        soya.Volume.begin_round(self)

        self.tools['dsync']['pct'] = 100.0 * self.arrived_chunks / self.total_chunks

        if self.nodes_not_done > 0:
            int_time = int(self.elapsed)
            if int_time < len(self.set_log):
                self.tools['SET']['pct'] = self.set_log[int_time]
            else:
                self.tools['SET']['pct'] = 100

            if int_time < len(self.rsync_log):
                self.tools['rsync']['pct'] = self.rsync_log[int_time] 
            else:
                self.tools['rsync']['pct'] = 100


    def advance_time(self, proportion):
        soya.Volume.advance_time(self, proportion)

        if self.paused:
            return

        self.ticks += 1.0 * proportion
        if self.ticks > GRANULARITY / soya.MAIN_LOOP.round_duration / SPEEDUP:
            self.ticks = 0.0
            self.elapsed += GRANULARITY


class MainIdler(soya.MainLoop):
    def __init__(self):
        self.events = []

        # Creates the scene.
        self.scene = soya.World()
        soya.MainLoop.__init__(self, self.scene)

        # the simulation holds the demo state
        self.sim = Simulation(self.scene)

        # Creates a light.
        self.light = soya.Light(self.scene)
        self.light.set_xyz(0.0, 8.0, 0.0)

        # Creates a camera
        self.camera = MoveableCamera(self.scene)
        self.camera.look_at(soya.Point(self.scene, 0,0,0))

        # Create root widget and populate it with controls/display elements
        self.root = pudding.core.RootWidget(width=1024, height=768)

        ifont = soya.Font(pudding.sysfont.SysFont('Neo Sans Intel'), 60, 55)
        myfont = soya.Font(pudding.sysfont.SysFont('sans, freesans'), 40, 35)
        #print "Available fonts are :", pudding.sysfont.get_fonts()
        #print "Choosen font :", myfont

        self.title = pudding.control.SimpleLabel(self.root, label=Demo.title, font=ifont)
        self.title.top = self.title.left = 5
        self.title.color = (0.5, 0.5, 1., 1.)

        self.time_label = TimeLabel(self.root, sim=self.sim, font=myfont)

        self.meters = pudding.container.VerticalContainer(self.root)
        self.meters.height = 175
        self.meters.set_pos_bottom_right(bottom=5)
        self.meters.left = 10
        self.meters.anchors = pudding.ANCHOR_BOTTOM_LEFT
        self.meters.padding = 0

        self.dsync_done_meter = DoneMeter(self.meters, sim=self.sim, font=myfont, tool='dsync')
        self.bt_done_meter = DoneMeter(self.meters, sim=self.sim, font=myfont, tool='SET')
        self.rsync_done_meter = DoneMeter(self.meters, sim=self.sim, font=myfont, tool='rsync')

        self.root.add_child(self.camera)
        soya.set_root_widget(self.root)

    def begin_round(self):
        soya.MainLoop.begin_round(self)
        self.events = pudding.process_event()

        for event in soya.MAIN_LOOP.events:
            if event[0] == soya.sdlconst.MOUSEBUTTONDOWN:
                mouse = self.camera.coord2d_to_3d(event[2], event[3])
                result = self.scene.raypick(self.camera, self.camera.vector_to(mouse))
                if result:
                    self.impact, normal = result
                    obj = self.impact.parent.parent
                    if isinstance(obj, NodeWorld):
                        self.sim.clicked_node(obj)
            if event[0] == soya.sdlconst.KEYUP:
                if event[1] == soya.sdlconst.K_SPACE:  
                    self.sim.paused = not self.sim.paused

#################
# SETUP
#################

class Demo:
    STATE_MAIN = 0
    STATE_END = 1
    title = "DOT Dsync Demo"

    def __init__(self, datafile=None, fullscreen=False):
        soya.init(width=1024, height=768, title=Demo.title, \
                  resizeable=False, fullscreen=fullscreen)
        #soya.path.append(os.path.join(os.path.dirname(sys.argv[0]), "data"))

        # initialise pudding (for widgets)
        pudding.init()
        
        self.state = Demo.STATE_MAIN

    def start(self):
        while (self.state != None and self.state != Demo.STATE_END):
            idler = MainIdler()
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
