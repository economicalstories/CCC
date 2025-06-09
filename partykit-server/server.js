export default class CaptionRoom {
  constructor(party) {
    this.party = party;
    this.connections = new Map(); // connection -> participant info
    this.deviceConnections = new Map(); // deviceUuid -> connection
    this.joinRequests = new Map(); // deviceUuid -> join request info
    
    // Enhanced participant state management
    this.participantStates = new Map(); // deviceUuid -> participant state object
    this.activeSpeaker = null;
    this.currentMessageId = null;
    
    // Constants
    this.HEARTBEAT_TIMEOUT = 60 * 60 * 1000; // 60 minutes in milliseconds
    this.HEARTBEAT_CHECK_INTERVAL = 60 * 1000; // Check every minute
    
    // Access key for authentication
    this.ACCESS_KEY = party.env.ACCESS_KEY;
    console.log(`🔑 Server initialized with access key: ${this.ACCESS_KEY ? 'SET' : 'NOT SET'}`);
    
    // Load participant states from storage on startup
    this.loadParticipantStates();
    
    // Start periodic heartbeat health check
    this.startHeartbeatHealthCheck();
    
    console.log(`🏠 Room ${this.party.id} initialized with enhanced state management`);
  }

  // Validate access key from WebSocket connection
  validateAccessKey(request) {
    // If no access key is configured, allow all connections (development mode)
    if (!this.ACCESS_KEY) {
      console.log(`⚠️ No ACCESS_KEY configured - allowing all connections`);
      return true;
    }

    // Extract access key from URL query parameters
    const url = new URL(request.url);
    const providedKey = url.searchParams.get('key');
    
    console.log(`🔍 Validating access key: provided=${providedKey ? 'YES' : 'NO'}, valid=${providedKey === this.ACCESS_KEY}`);
    
    if (!providedKey) {
      console.log(`❌ No access key provided in URL`);
      return false;
    }
    
    if (providedKey !== this.ACCESS_KEY) {
      console.log(`❌ Invalid access key provided`);
      return false;
    }
    
    console.log(`✅ Valid access key provided`);
    return true;
  }

  // Load participant states from persistent storage
  async loadParticipantStates() {
    try {
      const storedStates = await this.party.storage.get("participantStates");
      if (storedStates) {
        this.participantStates = new Map(Object.entries(storedStates));
        console.log(`📂 Loaded ${this.participantStates.size} participant states from storage`);
        for (const [id, state] of this.participantStates) {
          console.log(`  - ${state.displayName} (${id.substring(0, 8)}...) -> ${state.state}`);
          // Mark all loaded participants as timed out initially (they'll reconnect if still active)
          if (state.state === 'active') {
            state.state = 'timed_out';
            state.connection = null;
          }
        }
      } else {
        console.log(`📂 No stored participant states found - starting fresh`);
      }
    } catch (e) {
      console.log(`⚠️ Failed to load participant states: ${e.message}`);
    }
  }

  // Save participant states to persistent storage
  async saveParticipantStates() {
    try {
      const statesToSave = {};
      for (const [id, state] of this.participantStates) {
        // Don't save connection objects (they're not serializable)
        statesToSave[id] = {
          deviceUuid: state.deviceUuid,
          displayName: state.displayName,
          state: state.state,
          lastHeartbeat: state.lastHeartbeat,
          lastSeen: state.lastSeen,
          joinedAt: state.joinedAt
        };
      }
      await this.party.storage.put("participantStates", statesToSave);
      console.log(`💾 Saved ${Object.keys(statesToSave).length} participant states to storage`);
    } catch (e) {
      console.log(`⚠️ Failed to save participant states: ${e.message}`);
    }
  }

  // Participant states: 'active', 'timed_out', 'declined'
  getParticipantState(deviceUuid) {
    return this.participantStates.get(deviceUuid) || null;
  }
  
  setParticipantState(deviceUuid, displayName, state, connection = null) {
    const now = Date.now();
    const existing = this.participantStates.get(deviceUuid);
    
    this.participantStates.set(deviceUuid, {
      deviceUuid,
      displayName,
      state, // 'active', 'timed_out', 'declined'
      lastHeartbeat: state === 'active' ? now : (existing?.lastHeartbeat || now),
      lastSeen: now,
      connection: connection || existing?.connection || null,
      joinedAt: existing?.joinedAt || now
    });
    
    console.log(`📋 Set participant state: ${displayName} -> ${state}`);
    
    // Save to storage asynchronously
    this.saveParticipantStates().catch(e => 
      console.log(`⚠️ Failed to save states after update: ${e.message}`)
    );
    
    this.broadcastFullRoomState();
  }
  
  // Get current room state with all participant categories
  getRoomState() {
    const participants = {
      active: [],
      timedOut: [],
      declined: []
    };
    
    for (const [deviceUuid, participant] of this.participantStates) {
      const participantInfo = {
        id: deviceUuid,
        deviceUuid: deviceUuid,
        name: participant.displayName,
        displayName: participant.displayName,
        lastHeartbeat: participant.lastHeartbeat,
        lastSeen: participant.lastSeen,
        joinedAt: participant.joinedAt
      };
      
      switch (participant.state) {
        case 'active':
          participants.active.push(participantInfo);
          break;
        case 'timed_out':
          participants.timedOut.push(participantInfo);
          break;
        case 'declined':
          participants.declined.push(participantInfo);
          break;
      }
    }
    
    return {
      participants,
      activeSpeaker: null, // Always null in concurrent mode
      concurrentMode: true, // Indicate this room supports concurrent speaking
      roomId: this.party.id,
      timestamp: Date.now()
    };
  }
  
  // Broadcast full room state to all active connections
  broadcastFullRoomState() {
    const roomState = this.getRoomState();
    const message = JSON.stringify({
      type: "roomState",
      data: roomState
    });
    
    console.log(`📢 Broadcasting full room state: ${roomState.participants.active.length} active, ${roomState.participants.timedOut.length} timed out, ${roomState.participants.declined.length} declined`);
    
    // Send to all active connections
    for (const [connection, participant] of this.connections) {
      try {
        connection.send(message);
      } catch (e) {
        console.log(`⚠️ Failed to send to ${participant.displayName}: ${e.message}`);
      }
    }
  }
  
  // Periodic check for timed out participants
  startHeartbeatHealthCheck() {
    setInterval(() => {
      this.checkHeartbeatHealth();
    }, this.HEARTBEAT_CHECK_INTERVAL);
  }
  
  checkHeartbeatHealth() {
    const now = Date.now();
    let stateChanged = false;
    
    for (const [deviceUuid, participant] of this.participantStates) {
      if (participant.state === 'active') {
        const timeSinceLastHeartbeat = now - participant.lastHeartbeat;
        
        if (timeSinceLastHeartbeat > this.HEARTBEAT_TIMEOUT) {
          console.log(`⏰ ${participant.displayName} timed out (${Math.round(timeSinceLastHeartbeat / 1000 / 60)} minutes since last heartbeat)`);
          
          // Move to timed out state
          participant.state = 'timed_out';
          participant.lastSeen = now;
          
          // Remove from active connections
          if (participant.connection) {
            this.connections.delete(participant.connection);
            this.deviceConnections.delete(deviceUuid);
            participant.connection = null;
          }
          
          // Clear as active speaker if they were speaking
          if (this.activeSpeaker === deviceUuid) {
            this.activeSpeaker = null;
          }
          
          stateChanged = true;
        }
      }
    }
    
    if (stateChanged) {
      // Save to storage asynchronously
      this.saveParticipantStates().catch(e => 
        console.log(`⚠️ Failed to save states after timeout check: ${e.message}`)
      );
      this.broadcastFullRoomState();
    }
  }

  async onConnect(connection, ctx) {
    console.log(`🔌 New connection to room ${this.party.id}: ${connection.id}`);
    
    // Validate access key before proceeding
    if (!this.validateAccessKey(ctx.request)) {
      console.log(`🚫 Rejecting connection ${connection.id} - invalid or missing access key`);
      connection.close(1008, "Invalid or missing access key");
      return;
    }
    
    console.log(`✅ Connection ${connection.id} authorized with valid access key`);
    
    connection.addEventListener("message", (evt) => {
      this.handleMessage(connection, evt.data);
    });

    connection.addEventListener("close", () => {
      this.handleDisconnect(connection);
    });

    // Send current room state to new connection
    const roomState = this.getRoomState();
    connection.send(JSON.stringify({
      type: "roomState",
      data: roomState
    }));
    
    console.log(`📤 Sent room state to new connection: ${roomState.participants.active.length} active participants`);
  }

  handleMessage(connection, message) {
    try {
      const data = JSON.parse(message);
      
      switch (data.type) {
        case "checkRoom":
          this.handleCheckRoom(connection, data);
          break;
        case "join":
          this.handleJoin(connection, data);
          break;
        case "requestSpeak":
          this.handleRequestSpeak(connection, data);
          break;
        case "stopSpeak":
          this.handleStopSpeak(connection, data);
          break;
        case "caption":
          this.handleCaption(connection, data);
          break;
        case "buttonPressed":
          this.handleButtonPressed(connection, data);
          break;
        case "buttonReleased":
          this.handleButtonReleased(connection, data);
          break;
        case "heartbeat":
          this.handleHeartbeat(connection, data);
          break;
        case "approveJoin":
          this.handleApproveJoin(connection, data);
          break;
        case "declineJoin":
          this.handleDeclineJoin(connection, data);
          break;
        case "cancelJoin":
          this.handleCancelJoin(connection, data);
          break;
        case "removeParticipant":
          this.handleRemoveParticipant(connection, data);
          break;
        case "liveSTT":
          this.handleLiveSTT(connection, data);
          break;
        case "liveTextContent":
          this.handleLiveTextContent(connection, data);
          break;
        case "liveTextingStatus":
          this.handleLiveTextingStatus(connection, data);
          break;
        default:
          console.log(`❓ Unknown message type: ${data.type}`);
      }
    } catch (e) {
      console.error("❌ Error handling message:", e);
    }
  }

  handleCheckRoom(connection, data) {
    const roomState = this.getRoomState();
    const totalParticipants = roomState.participants.active.length + 
                             roomState.participants.timedOut.length;
    const isEmpty = totalParticipants === 0;
    
    connection.send(JSON.stringify({
      type: "roomStatus",
      data: {
        participantCount: totalParticipants,
        activeCount: roomState.participants.active.length,
        timedOutCount: roomState.participants.timedOut.length,
        declinedCount: roomState.participants.declined.length,
        isEmpty: isEmpty
      }
    }));
  }

  handleJoin(connection, data) {
    const deviceUuid = data.deviceUuid || data.participantId;
    const displayName = data.displayName || data.name;
    
    console.log(`🚪 Join request from ${displayName} (device: ${deviceUuid.substring(0, 8)}...)`);
    console.log(`📊 Current participant states in memory: ${this.participantStates.size} total`);
    for (const [id, state] of this.participantStates) {
      console.log(`  - ${state.displayName} (${id.substring(0, 8)}...) -> ${state.state}`);
    }
    
    // Check existing participant state
    const existingState = this.getParticipantState(deviceUuid);
    console.log(`🔍 Existing state for ${deviceUuid.substring(0, 8)}...: ${existingState ? existingState.state : 'NOT FOUND'}`);
    
    if (existingState) {
      if (existingState.state === 'declined') {
        console.log(`❌ ${displayName} was previously declined - requiring approval`);
        // Declined users need approval to rejoin
        this.requireApproval(connection, deviceUuid, displayName);
        return;
      } else if (existingState.state === 'timed_out') {
        console.log(`🔄 ${displayName} returning from timeout - auto-approving`);
        // Timed out users can rejoin automatically
        this.approveParticipant(connection, deviceUuid, displayName);
        return;
      } else if (existingState.state === 'active') {
        console.log(`⚠️ ${displayName} is already active - updating connection`);
        // Update connection for active participant
        this.updateParticipantConnection(connection, deviceUuid, displayName);
        return;
      }
    }
    
    // New participant
    const roomState = this.getRoomState();
    const activeParticipants = roomState.participants.active;
    const totalParticipants = this.participantStates.size;
    
    console.log(`📊 Room state: ${activeParticipants.length} active, ${totalParticipants} total in memory`);
    
    if (activeParticipants.length === 0) {
      if (totalParticipants === 0) {
        console.log(`🎉 ${displayName} joining truly empty room - auto-approving`);
      } else {
        console.log(`🔄 ${displayName} joining room with no active participants (possibly after server restart) - auto-approving`);
      }
      this.approveParticipant(connection, deviceUuid, displayName);
    } else {
      console.log(`👥 ${displayName} requesting to join occupied room (${activeParticipants.length} active) - requiring approval`);
      this.requireApproval(connection, deviceUuid, displayName);
    }
  }
  
  requireApproval(connection, deviceUuid, displayName) {
    // Store the join request
    this.joinRequests.set(deviceUuid, {
      connection: connection,
      deviceUuid: deviceUuid,
      requesterName: displayName,
      timestamp: Date.now()
    });
    
    console.log(`📋 Stored join request for ${displayName}`);
    
    // Send "awaiting approval" to requester
    connection.send(JSON.stringify({
      type: "awaitingApproval",
      message: `Waiting for approval from room members...`
    }));
    
    // Broadcast join request to active participants only
    const joinRequestMessage = JSON.stringify({
      type: "joinRequest",
      data: {
        requesterId: deviceUuid,
        requesterName: displayName,
        timestamp: Date.now()
      }
    });
    
    this.broadcast(joinRequestMessage, connection); // Exclude the requester
    console.log(`🔔 Broadcasted join request from ${displayName} to active participants`);
    
    // Set timeout for auto-decline (24 hours)
    setTimeout(() => {
      if (this.joinRequests.has(deviceUuid)) {
        const request = this.joinRequests.get(deviceUuid);
        this.joinRequests.delete(deviceUuid);
        request.connection.send(JSON.stringify({
          type: "joinDenied",
          reason: "Request timed out after 24 hours"
        }));
        console.log(`⏰ Join request from ${displayName} timed out`);
      }
    }, 24 * 60 * 60 * 1000);
  }
  
  approveParticipant(connection, deviceUuid, displayName) {
    // Add to active participants
    this.connections.set(connection, {
      deviceUuid: deviceUuid,
      displayName: displayName,
      connectionId: connection.id
    });
    this.deviceConnections.set(deviceUuid, connection);
    
    // Set as active in state
    this.setParticipantState(deviceUuid, displayName, 'active', connection);
    
    console.log(`✅ ${displayName} approved and added as active participant`);
  }
  
  updateParticipantConnection(connection, deviceUuid, displayName) {
    // Update connection mapping
    this.connections.set(connection, {
      deviceUuid: deviceUuid,
      displayName: displayName,
      connectionId: connection.id
    });
    this.deviceConnections.set(deviceUuid, connection);
    
    // Update participant state with new connection
    const participant = this.getParticipantState(deviceUuid);
    if (participant) {
      participant.connection = connection;
      participant.lastHeartbeat = Date.now();
      participant.lastSeen = Date.now();
    }
    
    // Broadcast updated state
    this.broadcastFullRoomState();
    
    console.log(`🔄 Updated connection for ${displayName}`);
  }

  handleHeartbeat(connection, data) {
    let participant = this.connections.get(connection);
    if (!participant) {
      // Try to fix broken connection mapping
      const participantId = data.participantId;
      if (participantId) {
        const participantState = this.getParticipantState(participantId);
        if (participantState && participantState.state === 'active') {
          console.log(`🔧 Fixing broken connection mapping for ${participantState.displayName}`);
          this.updateParticipantConnection(connection, participantId, participantState.displayName);
          participant = this.connections.get(connection);
        }
      }
      
      if (!participant) {
        console.log("⚠️ Heartbeat from unknown participant");
        return;
      }
    }
    
    // Update heartbeat timestamp
    const participantState = this.getParticipantState(participant.deviceUuid);
    if (participantState) {
      participantState.lastHeartbeat = Date.now();
      participantState.lastSeen = Date.now();
    }
    
    // Relay heartbeat to ALL participants INCLUDING sender for connection health confirmation
    this.broadcast(JSON.stringify({
      type: "heartbeat",
      data: {
        participantId: participant.deviceUuid,
        participantName: participant.displayName,
        isPressed: data.isPressed || false,
        currentText: data.currentText || '',
        isTexting: data.isTexting || false,
        timestamp: data.timestamp || Date.now()
      }
    })); // Include sender so they can confirm their own connection health
  }

  handleRequestSpeak(connection, data) {
    const participant = this.connections.get(connection);
    if (!participant) return;
    
    console.log(`🎤 ${participant.displayName} started speaking (concurrent mode)`);
    
    // In concurrent mode, don't set a single active speaker
    // Just broadcast that this person started speaking
    this.broadcast(JSON.stringify({
      type: "speakerChanged",
      data: {
        speakerId: participant.deviceUuid,
        speakerName: participant.displayName,
        action: "started" // New field to indicate start/stop
      }
    }));
    
    // Don't update room state activeSpeaker in concurrent mode
    // this.activeSpeaker = participant.deviceUuid;
    // this.broadcastFullRoomState();
  }

  handleStopSpeak(connection, data) {
    const participant = this.connections.get(connection);
    if (!participant) return;
    
    console.log(`🎤 ${participant.displayName} stopped speaking`);
    
    this.broadcast(JSON.stringify({
      type: "speakerStopped", 
      data: {
        speakerId: participant.deviceUuid,
        action: "stopped" // New field to indicate start/stop
      }
    }));
    
    // In concurrent mode, don't clear single active speaker
    // this.activeSpeaker = null;
    // this.broadcastFullRoomState();
  }

  handleCaption(connection, data) {
    const participant = this.connections.get(connection);
    if (!participant) return;
    
    const messageId = data.messageId;
    console.log(`📨 Caption from ${participant.displayName}: messageId=${messageId}, isFinal=${data.isFinal}`);
    
    this.broadcast(JSON.stringify({
      type: "caption",
      data: {
        messageId: messageId,
        speakerId: participant.deviceUuid,
        speakerName: participant.displayName,
        text: data.text,
        isFinal: data.isFinal,
        timestamp: Date.now()
      }
    }));
  }

  handleApproveJoin(connection, data) {
    const approver = this.connections.get(connection);
    if (!approver) return;
    
    const requesterId = data.requesterId;
    console.log(`👍 ${approver.displayName} wants to approve ${requesterId}`);
    
    const request = this.joinRequests.get(requesterId);
    if (!request) {
      console.log(`❌ No pending request found for ${requesterId}`);
      return;
    }
    
    this.joinRequests.delete(requesterId);
    console.log(`✅ ${approver.displayName} approved ${request.requesterName}`);
    
    // Add the participant as active
    this.approveParticipant(request.connection, requesterId, request.requesterName);
    
    // Notify about approval
    this.broadcast(JSON.stringify({
      type: "joinApproved",
      data: {
        requesterName: request.requesterName,
        approverName: approver.displayName
      }
    }), request.connection);
  }
  
  handleDeclineJoin(connection, data) {
    const decliner = this.connections.get(connection);
    if (!decliner) return;
    
    const requesterId = data.requesterId;
    const request = this.joinRequests.get(requesterId);
    if (!request) return;
    
    this.joinRequests.delete(requesterId);
    console.log(`❌ ${decliner.displayName} declined ${request.requesterName}`);
    
    // Mark as declined
    this.setParticipantState(requesterId, request.requesterName, 'declined');
    
    // Notify the requester
    request.connection.send(JSON.stringify({
      type: "joinDenied",
      reason: "Access declined by room members"
    }));
    
    // Notify others
    this.broadcast(JSON.stringify({
      type: "joinDeclined",
      data: {
        requesterName: request.requesterName,
        declinerName: decliner.displayName
      }
    }), request.connection);
  }

  handleCancelJoin(connection, data) {
    // Find and remove the join request for this connection
    for (const [requesterId, request] of this.joinRequests.entries()) {
      if (request.connection === connection) {
        this.joinRequests.delete(requesterId);
        console.log(`🚫 ${request.requesterName} cancelled their join request`);
        
        this.broadcast(JSON.stringify({
          type: "joinCancelled",
          data: {
            requesterName: request.requesterName
          }
        }));
        break;
      }
    }
  }

  handleRemoveParticipant(connection, data) {
    const remover = this.connections.get(connection);
    if (!remover) return;
    
    const participantId = data.participantId;
    const participantState = this.getParticipantState(participantId);
    
    if (!participantState) {
      console.log(`❌ Cannot remove unknown participant: ${participantId}`);
      return;
    }
    
    console.log(`🗑️ ${remover.displayName} removing ${participantState.displayName}`);
    
    // Mark as declined
    this.setParticipantState(participantId, participantState.displayName, 'declined');
    
    // Disconnect if they have an active connection
    if (participantState.connection) {
      this.connections.delete(participantState.connection);
      this.deviceConnections.delete(participantId);
      participantState.connection = null;
    }
    
    // In concurrent mode, broadcast that they stopped speaking when removed
    this.broadcast(JSON.stringify({
      type: "speakerStopped",
      data: {
        speakerId: participantId,
        action: "removed"
      }
    }));
    
    // Broadcast updated state
    this.broadcastFullRoomState();
  }

  handleButtonPressed(connection, data) {
    const participant = this.connections.get(connection);
    if (!participant) return;
    
    this.broadcast(JSON.stringify({
      type: "buttonPressed", 
      data: {
        participantId: participant.deviceUuid,
        participantName: participant.displayName,
        isPressed: true,
        timestamp: Date.now()
      }
    }));
  }

  handleButtonReleased(connection, data) {
    const participant = this.connections.get(connection);
    if (!participant) return;
    
    this.broadcast(JSON.stringify({
      type: "buttonReleased",
      data: {
        participantId: participant.deviceUuid,
        participantName: participant.displayName,
        isPressed: false,
        timestamp: Date.now()
      }
    }));
  }

  handleLiveSTT(connection, data) {
    const participant = this.connections.get(connection);
    if (!participant) return;
    
    this.broadcast(JSON.stringify({
      type: "liveSTT",
      data: {
        participantId: participant.deviceUuid,
        text: data.text,
        timestamp: Date.now()
      }
    }), connection);
  }

  handleLiveTextContent(connection, data) {
    const participant = this.connections.get(connection);
    if (!participant) return;
    
    this.broadcast(JSON.stringify({
      type: "liveTextContent",
      data: {
        participantId: participant.deviceUuid,
        text: data.text,
        timestamp: Date.now()
      }
    }), connection);
  }

  handleLiveTextingStatus(connection, data) {
    const participant = this.connections.get(connection);
    if (!participant) return;
    
    this.broadcast(JSON.stringify({
      type: "liveTextingStatus",
      data: {
        participantId: participant.deviceUuid,
        isTexting: data.isTexting,
        timestamp: Date.now()
      }
    }), connection);
  }

  handleDisconnect(connection, skipBroadcast = false) {
    const participant = this.connections.get(connection);
    console.log(`🚪 Connection ${connection.id} disconnecting`);
    
    if (participant) {
      console.log(`👋 ${participant.displayName} connection lost`);
      
      // Remove from connections but keep in participant state as active
      // They might reconnect soon, so don't immediately mark as timed out
      this.connections.delete(connection);
      this.deviceConnections.delete(participant.deviceUuid);
      
      // Update participant state - clear connection but keep as active
      const participantState = this.getParticipantState(participant.deviceUuid);
      if (participantState) {
        participantState.connection = null;
        participantState.lastSeen = Date.now();
        // Keep as active - they'll be moved to timed_out by the health check if they don't reconnect
      }
      
             // In concurrent mode, just broadcast that they stopped speaking if they disconnect
       if (!skipBroadcast) {
         this.broadcast(JSON.stringify({
           type: "speakerStopped",
           data: {
             speakerId: participant.deviceUuid,
             action: "disconnected"
           }
         }));
       }
      
      // Send updated room state (they're still active, just disconnected)
      if (!skipBroadcast) {
        this.broadcastFullRoomState();
      }
    } else {
      // Check for abandoned join requests
      for (const [requesterId, request] of this.joinRequests.entries()) {
        if (request.connection === connection) {
          console.log(`🧹 Cleaning up abandoned join request for ${request.requesterName}`);
          this.joinRequests.delete(requesterId);
          break;
        }
      }
    }
  }

  broadcast(message, excludeConnection = null) {
    for (const [connection, participant] of this.connections) {
      if (connection !== excludeConnection) {
        try {
          connection.send(message);
        } catch (e) {
          console.log(`⚠️ Failed to send to ${participant.displayName}: ${e.message}`);
        }
      }
    }
  }
} 