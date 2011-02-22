package net.systemeD.halcyon.connection {
    import flash.geom.Point;
    import flash.geom.Rectangle;
    
    import net.systemeD.halcyon.connection.actions.*;

    public class Way extends Entity {
        private var nodes:Array;
		private var edge_l:Number;
		private var edge_r:Number;
		private var edge_t:Number;
		private var edge_b:Number;
		public static var entity_type:String = 'way';

        public function Way(id:Number, version:uint, tags:Object, loaded:Boolean, nodes:Array, uid:Number = NaN, timestamp:String = null) {
            super(id, version, tags, loaded, uid, timestamp);
            this.nodes = nodes;
			for each (var node:Node in nodes) { node.addParent(this); }
			calculateBbox();
        }

		public function update(version:uint, tags:Object, loaded:Boolean, parentsLoaded:Boolean, nodes:Array, uid:Number = NaN, timestamp:String = null):void {
			var node:Node;
			for each (node in this.nodes) { node.removeParent(this); }
			updateEntityProperties(version,tags,loaded,parentsLoaded,uid,timestamp); this.nodes=nodes;
			for each (node in nodes) { node.addParent(this); }
			calculateBbox();
		}
		
        public function get length():uint {
            return nodes.length;
        }

		private function calculateBbox():void {
			edge_l=999999; edge_r=-999999;
			edge_b=999999; edge_t=-999999;
			for each (var node:Node in nodes) { expandBbox(node); }
		}

		public function expandBbox(node:Node):void {
			edge_l=Math.min(edge_l,node.lon);
			edge_r=Math.max(edge_r,node.lon);
			edge_b=Math.min(edge_b,node.lat);
			edge_t=Math.max(edge_t,node.lat);
		}
		
		/** True if the bounding box for the way intersects the given rectangle. This means false
		 * positives, for example if the way does a horseshoe bend around the outside of the rectangle. */
		public override function within(left:Number,right:Number,top:Number,bottom:Number):Boolean {
			if (!edge_l ||
				(edge_l<left   && edge_r<left  ) ||
			    (edge_l>right  && edge_r>right ) ||
			    (edge_b<bottom && edge_t<bottom) ||
			    (edge_b>top    && edge_b>top   ) || deleted) { return false; }
			return true;
		}
        
        /** Returns the Node by index. */
        public function getNode(index:uint):Node {
            return nodes[index];
        }

        /** @return nodes[0] */
        public function getFirstNode():Node {
            return nodes[0];
        }

		/** @return nodes[node.length-1] */
		public function getLastNode():Node {
			return nodes[nodes.length-1];
		}
		
		/** Given one node, return the next in sequence, cycling around a loop if necessary. */
		// TODO make behave correctly for P-shaped topologies?
		public function getNextNode(node:Node):Node {
			// If the last node in a loop is selected, this behaves correctly.
		    var i:uint = indexOfNode(node);
		    if(i < length-1)
	            return nodes[i+1];
	        return null;
	        // What should happen for very short lengths?      
		}
        
        // TODO make behave correctly for P-shaped topologies?
        /** Given one node, return the previous, cycling around a loop if necessary. */
        public function getPrevNode(node:Node):Node {
            var i:uint = indexOfNode(node);
            if(i > 0)
                return nodes[i-1];
            if(i == 0 && isArea() )
                return nodes[nodes.length - 2]
            return null;
            // What should happen for very short lengths?      
        }

        /** Stick an extra node at the given location. */
        public function insertNode(index:uint, node:Node, performAction:Function):void {
			performAction(new AddNodeToWayAction(this, node, nodes, index));
        }

        /** Stick an extra node at the end. */
        public function appendNode(node:Node, performAction:Function):uint {
			performAction(new AddNodeToWayAction(this, node, nodes, -1));
            return nodes.length + 1;
        }
        
        /** Stick an extra node at the start. */
        public function prependNode(node:Node, performAction:Function):uint {
			performAction(new AddNodeToWayAction(this, node, nodes, 0));
            return nodes.length + 1;
        }
        
        /** Return the index of the Node, or -1 if not found */
        public function indexOfNode(node:Node):int {
            return nodes.indexOf(node);
        }

		/** Does the way have this Node once, and once only? */
		public function hasOnceOnly(node:Node):Boolean {
			return nodes.indexOf(node)==nodes.lastIndexOf(node);
		}
		
		/** Does the way have any nodes that are .locked? */
		public function hasLockedNodes():Boolean {
			for each (var node:Node in nodes) {
				if (node.locked) { return true; }
			}
			return false;
		}

		public function removeNode(node:Node, performAction:Function):void {
			performAction(new RemoveNodeFromWayAction(this, node, nodes));
		}

        public function removeNodeByIndex(index:uint, performAction:Function, fireEvent:Boolean=true):void {
            performAction(new RemoveNodeByIndexAction(this, nodes, index, fireEvent));
        }

		public function sliceNodes(start:int,end:int):Array {
			return nodes.slice(start,end);
		}

        public function deleteNodesFrom(start:int, performAction:Function):void {
            for (var i:int=nodes.length-1; i>=start; i--) {
              performAction(new RemoveNodeByIndexAction(this, nodes, i));
            }
            markDirty();
        }

		/** Merges another way into this one, removing the other one. */
		public function mergeWith(way:Way,topos:int,frompos:int, performAction:Function):void {
			performAction(new MergeWaysAction(this, way, topos, frompos));
		}
		
		public function addToEnd(topos:int,node:Node, performAction:Function):void {
			if (topos==0) {
				if (nodes[0]==node) { return; }
				prependNode(node, performAction);
			} else {
				if (nodes[nodes.length-1]==node) { return; }
				appendNode(node, performAction);
			}
		}

        public function reverseNodes(performAction:Function):void {
            performAction(new ReverseNodesAction(this, nodes));
        }

        /**
         * Finds the 1st way segment which intersects the projected
         * coordinate and adds the node to that segment. If snap is
         * specified then the node is moved to exactly bisect the
         * segment.
         */
        public function insertNodeAtClosestPosition(newNode:Node, isSnap:Boolean, performAction:Function):int {
            var closestProportion:Number = 1;
            var newIndex:uint = 0;
            var nP:Point = new Point(newNode.lon, newNode.latp);
            var snapped:Point = null;
            
            for ( var i:uint; i < length - 1; i++ ) {
                var node1:Node = getNode(i);
                var node2:Node = getNode(i+1);
                var p1:Point = new Point(node1.lon, node1.latp);
                var p2:Point = new Point(node2.lon, node2.latp);
                
                var directDist:Number = Point.distance(p1, p2);
                var viaNewDist:Number = Point.distance(p1, nP) + Point.distance(nP, p2);
                        
                var proportion:Number = Math.abs(viaNewDist/directDist - 1);
                if ( proportion < closestProportion ) {
                    newIndex = i+1;
                    closestProportion = proportion;
                    snapped = calculateSnappedPoint(p1, p2, nP);
                }
            }
            
            // splice in new node
            if ( isSnap ) {
                newNode.setLonLatp(snapped.x, snapped.y, performAction);
            }
            insertNode(newIndex, newNode, performAction);
            return newIndex;
        }
        
        private function calculateSnappedPoint(p1:Point, p2:Point, nP:Point):Point {
            var w:Number = p2.x - p1.x;
            var h:Number = p2.y - p1.y;
            var u:Number = ((nP.x-p1.x) * w + (nP.y-p1.y) * h) / (w*w + h*h);
            return new Point(p1.x + u*w, p1.y+u*h);
        }
        
        public override function toString():String {
            return "Way("+id+"@"+version+"): "+getTagList()+
                     " "+nodes.map(function(item:Node,index:int, arr:Array):String {return item.id.toString();}).join(",");
        }

		/** Is this way a closed loop? */
		public function isArea():Boolean {
			if (nodes.length==0) { return false; }
			return (nodes[0].id==nodes[nodes.length-1].id && nodes.length>2);
		}
		
		/** Is that the first or last node of this way? */
		public function endsWith(node:Node):Boolean {
			return (nodes[0]==node || nodes[nodes.length-1]==node);
		}
		
		public override function remove(performAction:Function):void {
			performAction(new DeleteWayAction(this, setDeletedState, nodes));
		}

		public override function nullify():void {
			nullifyEntity();
			nodes=[];
			edge_l=edge_r=edge_t=edge_b=NaN;
		}
		
		public function get clockwise():Boolean {
			var lowest:uint=0;
			var xmin:Number=-999999; var ymin:Number=-999999;
			for (var i:uint=0; i<nodes.length; i++) {
				if      (nodes[i].latp> ymin) { lowest=i; xmin=nodes[i].lon; ymin=nodes[i].latp; }
				else if (nodes[i].latp==ymin
					  && nodes[i].lon > xmin) { lowest=i; xmin=nodes[i].lon; ymin=nodes[i].latp; }
			}
			return (this.onLeft(lowest)>0);
		}
		
		private function onLeft(j:uint):Number {
			var left:Number=0;
			var i:int, k:int;
			if (nodes.length>=3) {
				i=j-1; if (i==-1) { i=nodes.length-2; }
				k=j+1; if (k==nodes.length) { k=1; }
				left=((nodes[j].lon-nodes[i].lon) * (nodes[k].latp-nodes[i].latp) -
					  (nodes[k].lon-nodes[i].lon) * (nodes[j].latp-nodes[i].latp));
			}
			return left;
		}

        public function get angle():Number {
            var dx:Number = nodes[nodes.length-1].lon - nodes[0].lon;
            var dy:Number = nodes[nodes.length-1].latp - nodes[0].latp;
            if (dx != 0 || dy != 0) {
                return Math.atan2(dx,dy)*(180/Math.PI);
            } else {
                return 0;
            }
        }

		internal override function isEmpty():Boolean {
			return (deleted || (nodes.length==0));
		}

		/** @return 'way' */
		public override function getType():String {
			return 'way';
		}
		
		/** Is this way a 'way' (yes), a 'line' (if not closed), or an 'area' (if closed)? */
		public override function isType(str:String):Boolean {
			if (str=='way') return true;
			if (str=='line' && !isArea()) return true;
			if (str=='area' &&  isArea()) return true;
			return false;
		}
		
		/** Whether the way has a loop that joins back midway along its length */
		public function isPShape():Boolean {
			return getFirstNode() != getLastNode() && (!hasOnceOnly(getFirstNode()) || !hasOnceOnly(getLastNode()) );
		}
		
		/** Given a P-shaped way, return the index of midway node that one end connects back to. */
		public function getPJunctionNodeIndex():uint {
			if (isPShape()) {
			    if (hasOnceOnly(getFirstNode())) {
			        // nodes[0] is the free end
			        return nodes.indexOf(getLastNode());
			    } else {
			        // nodes[0] is in the loop
			        return nodes.lastIndexOf(getFirstNode());
			    }
			}
			return null;
		}
		
		/** Return list of nodes that the two ways have in common. */
		public function getJunctionsWith(way2: Way): Array {
			var js: Array = [];
			for (var i:uint = 0; i < length; i++) {
				if (way2.indexOfNode(nodes[i]) > 0) {
					js.push(nodes[i]);
				}
			}
			return js;
		}
		
		/** Returns the smallest rectangle that the way fits into. */
		public function get boundingBox(): Rectangle {
			return new Rectangle(edge_l, edge_t, edge_r-edge_l, edge_t-edge_b);
		}
    }
}
