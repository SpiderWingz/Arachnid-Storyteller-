(() => {
  const storyteller = window.ArachnidStoryteller;
  if (!storyteller) return;

  const drafts = new Map();
  let activeStoryId = null;
  let selectedNodeId = null;
  let editingTeleportId = null;
  let cutsceneSceneId = null;
  let editingSpawnPointId = null;
  let rtsOverlay = null;
  let rtsSnapshotTimer = null;
  let rtsStoryId = null;
  let rtsStory = null;
  let selectedRtsUnits = new Set();
  let rtsPatrolRoute = [];
  let pendingConnection = null;
  let idCounter = 0;
  let saveMessage = '';

  const nodeTypes = [
    { type: 'start', label: 'Start', inputs: false, outputs: ['next'] },
    { type: 'scene', label: 'Scene Beat', inputs: true, outputs: ['next'] },
    { type: 'delay', label: 'Delay', inputs: true, outputs: ['next'] },
    { type: 'branch', label: 'Branch', inputs: true, outputs: ['true', 'false'] },
    { type: 'random_branch', label: 'Random Branch', inputs: true, outputs: ['success', 'failure'] },
    { type: 'set_variable', label: 'Set Variable', inputs: true, outputs: ['next'] },
    { type: 'add_variable', label: 'Add Variable', inputs: true, outputs: ['next'] },
    { type: 'subtract_variable', label: 'Subtract Variable', inputs: true, outputs: ['next'] },
    { type: 'objective', label: 'Set Objective', inputs: true, outputs: ['next'] },
    { type: 'complete_objective', label: 'Complete Objective', inputs: true, outputs: ['next'] },
    { type: 'fail_objective', label: 'Fail Objective', inputs: true, outputs: ['next'] },
    { type: 'wait_objective', label: 'Wait for Objective', inputs: true, outputs: ['completed', 'failed'] },
    { type: 'wait_area', label: 'Wait for Area', inputs: true, outputs: ['next'] },
    { type: 'wait_all_in_area', label: 'Wait for All in Area', inputs: true, outputs: ['next'] },
    { type: 'wait_area_empty', label: 'Wait for Area Empty', inputs: true, outputs: ['next'] },
    { type: 'check_player_count', label: 'Check Player Count', inputs: true, outputs: ['true', 'false'] },
    { type: 'check_job', label: 'Check VORP Job', inputs: true, outputs: ['true', 'false'] },
    { type: 'check_entity_alive', label: 'Check Entity Alive', inputs: true, outputs: ['true', 'false'] },
    { type: 'and_node', label: 'AND Join', inputs: ['a', 'b'], outputs: ['next'] },
    { type: 'or_node', label: 'OR Join', inputs: ['a', 'b'], outputs: ['next'] },
    { type: 'not_node', label: 'NOT Pass Through', inputs: true, outputs: ['next'] },
    { type: 'play_cutscene', label: 'Play Cutscene', inputs: true, outputs: ['next'] },
    { type: 'wait_cutscene', label: 'Wait for Completion', inputs: true, outputs: ['next'] },
    { type: 'stop_cutscene', label: 'Stop Cutscene', inputs: true, outputs: ['next'] },
    { type: 'spawn_npc', label: 'Spawn NPC', inputs: true, outputs: ['next'] },
    { type: 'spawn_npc_group', label: 'Spawn NPC Group', inputs: true, outputs: ['next'] },
    { type: 'remove_npc', label: 'Remove Spawned NPCs', inputs: true, outputs: ['next'] },
    { type: 'wait_npc_death', label: 'Wait for NPC Death', inputs: true, outputs: ['next'] },
    { type: 'wait_npcs_dead', label: 'Wait for All NPCs Dead', inputs: true, outputs: ['next'] },
    { type: 'make_npc_hostile', label: 'Make NPCs Hostile', inputs: true, outputs: ['next'] },
    { type: 'set_npc_target', label: 'Set NPC Target', inputs: true, outputs: ['next'] },
    { type: 'patrol_route', label: 'Patrol Route', inputs: true, outputs: ['next'] },
    { type: 'stop_patrol', label: 'Stop NPC Orders', inputs: true, outputs: ['next'] },
    { type: 'spawn_prop', label: 'Spawn Prop', inputs: true, outputs: ['next'] },
    { type: 'delete_prop', label: 'Delete Spawned Props', inputs: true, outputs: ['next'] },
    { type: 'door_open', label: 'Open Registered Door', inputs: true, outputs: ['next'] },
    { type: 'door_close', label: 'Close Registered Door', inputs: true, outputs: ['next'] },
    { type: 'door_lock', label: 'Lock Registered Door', inputs: true, outputs: ['next'] },
    { type: 'door_unlock', label: 'Unlock Registered Door', inputs: true, outputs: ['next'] },
    { type: 'entity_enable', label: 'Enable Registered Entity', inputs: true, outputs: ['next'] },
    { type: 'entity_disable', label: 'Disable Registered Entity', inputs: true, outputs: ['next'] },
    { type: 'trigger_entity', label: 'Trigger Registered Entity', inputs: true, outputs: ['next'] },
    { type: 'play_sound', label: 'Play Sound', inputs: true, outputs: ['next'] },
    { type: 'stop_sound', label: 'Stop Sound', inputs: true, outputs: ['next'] },
    { type: 'screen_fade', label: 'Screen Fade', inputs: true, outputs: ['next'] },
    { type: 'announcement', label: 'Announcement', inputs: true, outputs: ['next'] },
    { type: 'subtitle', label: 'Subtitle', inputs: true, outputs: ['next'] },
    { type: 'screen_shake', label: 'Screen Shake', inputs: true, outputs: ['next'] },
    { type: 'send_message', label: 'Send Message', inputs: true, outputs: ['next'] },
    { type: 'freeze_players', label: 'Freeze Players', inputs: true, outputs: ['next'] },
    { type: 'unfreeze_players', label: 'Unfreeze Players', inputs: true, outputs: ['next'] },
    { type: 'set_health', label: 'Set Health', inputs: true, outputs: ['next'] },
    { type: 'set_armor', label: 'Set Armor', inputs: true, outputs: ['next'] },
    { type: 'give_weapon', label: 'Give Weapon', inputs: true, outputs: ['next'] },
    { type: 'strip_weapon', label: 'Remove Weapon', inputs: true, outputs: ['next'] },
    { type: 'strip_all_weapons', label: 'Strip All Weapons', inputs: true, outputs: ['next'] },
    { type: 'teleport_players', label: 'Teleport Players', inputs: true, outputs: ['next'] },
    { type: 'kill_players', label: 'Kill Players', inputs: true, outputs: ['next'] },
    { type: 'respawn_players', label: 'VORP Respawn', inputs: true, outputs: ['next'] },
    { type: 'change_job', label: 'VORP Change Job', inputs: true, outputs: ['next'] },
    { type: 'end', label: 'End', inputs: true, outputs: [] }
  ];
  const labels = Object.fromEntries(nodeTypes.map(item => [item.type, item.label]));
  const flowActionSettings = new Map([
    ['send_message', 'sendMessage'], ['freeze_players', 'freeze'], ['unfreeze_players', 'unfreeze'],
    ['set_health', 'health'], ['set_armor', 'armor'], ['give_weapon', 'giveWeapon'],
    ['strip_weapon', 'removeWeapon'], ['strip_all_weapons', 'stripAllWeapons'],
    ['teleport_players', 'teleport'], ['kill_players', 'kill'], ['respawn_players', 'respawn'], ['change_job', 'changeJob']
  ]);
  const worldNodeActions = new Map([
    ['door_open', 'open'], ['door_close', 'close'], ['door_lock', 'lock'], ['door_unlock', 'unlock'],
    ['entity_enable', 'enable'], ['entity_disable', 'disable'], ['trigger_entity', 'trigger']
  ]);

  const clone = value => JSON.parse(JSON.stringify(value));
  const element = (tag, text, cls) => {
    const result = document.createElement(tag);
    if (text !== undefined) result.textContent = String(text);
    if (cls) result.className = cls;
    return result;
  };
  const currentStory = () => storyteller.getSelectedStory?.() || null;

  function getDraft(story) {
    const key = String(story.id);
    if (!drafts.has(key)) {
      const saved = story.flow && Array.isArray(story.flow.nodes) && Array.isArray(story.flow.links)
        ? clone(story.flow)
        : { nodes: [], links: [] };
      drafts.set(key, saved);
    }
    if (activeStoryId !== key) {
      activeStoryId = key;
      selectedNodeId = null;
      pendingConnection = null;
      saveMessage = '';
    }
    return drafts.get(key);
  }

  function markChanged(message = 'Unsaved flow changes') {
    saveMessage = message;
    const story = currentStory();
    if (story?.id != null) drafts.set(String(story.id), drafts.get(String(story.id)));
    const status = document.getElementById('flow-save-state');
    if (status) status.textContent = saveMessage;
  }

  function uid(prefix) {
    idCounter += 1;
    return prefix + '-' + Date.now().toString(36) + '-' + idCounter.toString(36) + '-' + Math.random().toString(36).slice(2, 7);
  }

  function defaultData(type, story) {
    const state = storyteller.getState() || {};
    const areas = state.areas || [];
    const actionConfig = state.playerActions || {};
    const scene = (story.scenes || []).find(item => item.id != null);
    switch (type) {
      case 'scene': return { sceneId: scene ? Number(scene.id) : null };
      case 'delay': return { seconds: 3 };
      case 'branch': return { variable: 'choice', operator: '==', valueType: 'boolean', value: true };
      case 'random_branch': return { chance: 50 };
      case 'set_variable': return { variable: 'flag', valueType: 'boolean', value: true };
      case 'add_variable': return { variable: 'score', amount: 1 };
      case 'subtract_variable': return { variable: 'score', amount: 1 };
      case 'objective': return { text: '' };
      case 'wait_area': case 'wait_all_in_area': case 'wait_area_empty': return { areaId: areas.length ? Number(areas[0].id) : null };
      case 'check_player_count': return { operator: '>=', count: 1 };
      case 'check_job': {
        const job = (actionConfig.jobs || [])[0];
        return { jobName: job?.name || '' };
      }
      case 'check_entity_alive': return { targetId: state.world?.targets?.[0]?.id || '' };
      case 'play_cutscene': {
        const sceneWithRail = (story.scenes || []).find(item => (item.camera_points || []).length > 0);
        return { sceneId: sceneWithRail ? Number(sceneWithRail.id) : null };
      }
      case 'spawn_npc': case 'spawn_npc_group': {
        const npc = state.encounters?.models?.ped?.[0];
        const marker = story.spawnPoints?.find(item => item.kind === 'npc');
        return { model: npc?.name || '', spawnPointId: marker?.id ?? null, count: 3, health: 150 };
      }
      case 'spawn_prop': {
        const prop = state.encounters?.models?.prop?.[0];
        const marker = story.spawnPoints?.find(item => item.kind === 'prop');
        return { model: prop?.name || '', spawnPointId: marker?.id ?? null };
      }
      case 'set_npc_target': return { target: 'random' };
      case 'patrol_route': return { markerIds: (story.spawnPoints || []).filter(item => item.kind === 'patrol').slice(0, 2).map(item => Number(item.id)), waitSeconds: 3 };
      case 'door_open': case 'door_close': case 'door_lock': case 'door_unlock': case 'entity_enable': case 'entity_disable': case 'trigger_entity':
        return { targetId: state.world?.targets?.find(target => target.actions?.[worldNodeActions.get(type)])?.id || '' };
      case 'play_sound': case 'stop_sound': return { soundId: state.effects?.sounds?.[0]?.id || '', volume: 1, pitch: 100 };
      case 'screen_fade': return { direction: 'out', duration: 1 };
      case 'announcement': case 'subtitle': return { text: '', duration: 5 };
      case 'screen_shake': return { amplitude: 1, frequency: 1, duration: 2 };
      case 'send_message': return { target: 'all', message: '' };
      case 'freeze_players': case 'unfreeze_players': case 'strip_all_weapons': case 'kill_players': case 'respawn_players':
        return { target: 'all' };
      case 'set_health': return { target: 'all', health: 100 };
      case 'set_armor': return { target: 'all', armor: 0 };
      case 'give_weapon': case 'strip_weapon': {
        const weapon = (actionConfig.weapons || [])[0];
        return { target: 'all', weapon: weapon?.name || '', ammo: weapon?.defaultAmmo ?? 0 };
      }
      case 'teleport_players': return { target: 'all', markerId: story.teleports?.[0]?.id ?? null };
      case 'change_job': {
        const job = (actionConfig.jobs || [])[0];
        return { target: 'all', jobName: job?.name || '', grade: job?.grades?.[0] ?? 0 };
      }
      default: return {};
    }
  }

  function addNode(type) {
    const story = currentStory();
    if (!story?.id) return;
    const draft = getDraft(story);
    if (type === 'start' && draft.nodes.some(item => item.type === 'start')) {
      saveMessage = 'A flow can have one Start node.';
      renderEditor();
      return;
    }
    const index = draft.nodes.length;
    const node = {
      id: uid('node'), type,
      x: 40 + (index % 4) * 275,
      y: 45 + Math.floor(index / 4) * 185,
      data: defaultData(type, story)
    };
    draft.nodes.push(node);
    selectedNodeId = node.id;
    markChanged('Unsaved flow changes');
    renderEditor();
  }

  function linkPorts(fromNode, fromSocket, toNode, toSocket = 'in') {
    const story = currentStory();
    if (!story) return;
    const draft = getDraft(story);
    const source = draft.nodes.find(item => item.id === fromNode);
    const target = draft.nodes.find(item => item.id === toNode);
    if (!source || !target || source.type === 'end' || target.type === 'start' || source.id === target.id) return;
    const sourceType = nodeTypes.find(item => item.type === source.type);
    if (!sourceType?.outputs.includes(fromSocket)) return;
    if (draft.links.some(link => link.toNode === toNode && (link.toSocket || 'in') === toSocket)) {
      saveMessage = 'That input port already has a connection.';
      renderEditor();
      return;
    }
    draft.links.push({ id: uid('link'), fromNode, fromSocket, toNode, toSocket });
    pendingConnection = null;
    markChanged('Unsaved flow changes');
    renderEditor();
  }

  function portClick(role, nodeId, socket) {
    if (role === 'output') {
      if (pendingConnection && pendingConnection.fromNode === nodeId && pendingConnection.fromSocket === socket) {
        pendingConnection = null;
      } else {
        pendingConnection = { fromNode: nodeId, fromSocket: socket };
      }
      saveMessage = pendingConnection ? 'Output selected. Choose an input port.' : '';
      renderEditor();
      return;
    }
    if (!pendingConnection) {
      saveMessage = 'Choose an output port first.';
      renderEditor();
      return;
    }
    linkPorts(pendingConnection.fromNode, pendingConnection.fromSocket, nodeId, socket);
  }

  function drawConnections(canvas, svg, draft) {
    const width = Math.max(canvas.scrollWidth, 920);
    const height = Math.max(canvas.scrollHeight, 520);
    svg.setAttribute('width', String(width));
    svg.setAttribute('height', String(height));
    svg.setAttribute('viewBox', '0 0 ' + width + ' ' + height);
    svg.replaceChildren();
    const defs = document.createElementNS('http://www.w3.org/2000/svg', 'defs');
    const marker = document.createElementNS('http://www.w3.org/2000/svg', 'marker');
    marker.setAttribute('id', 'flow-arrow');
    marker.setAttribute('markerWidth', '8');
    marker.setAttribute('markerHeight', '8');
    marker.setAttribute('refX', '6');
    marker.setAttribute('refY', '3');
    marker.setAttribute('orient', 'auto');
    const arrow = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    arrow.setAttribute('d', 'M0,0 L0,6 L7,3 z');
    arrow.setAttribute('fill', '#d4ac6b');
    marker.append(arrow);
    defs.append(marker);
    svg.append(defs);
    const canvasRect = canvas.getBoundingClientRect();
    for (const link of draft.links) {
      const fromPort = canvas.querySelector('[data-role="output"][data-node-id="' + CSS.escape(link.fromNode) + '"][data-socket="' + CSS.escape(link.fromSocket) + '"]');
      const toPort = canvas.querySelector('[data-role="input"][data-node-id="' + CSS.escape(link.toNode) + '"][data-socket="' + CSS.escape(link.toSocket || 'in') + '"]');
      if (!fromPort || !toPort) continue;
      const a = fromPort.getBoundingClientRect(), b = toPort.getBoundingClientRect();
      const x1 = a.left + a.width / 2 - canvasRect.left + canvas.scrollLeft;
      const y1 = a.top + a.height / 2 - canvasRect.top + canvas.scrollTop;
      const x2 = b.left + b.width / 2 - canvasRect.left + canvas.scrollLeft;
      const y2 = b.top + b.height / 2 - canvasRect.top + canvas.scrollTop;
      const curve = Math.max(48, Math.abs(x2 - x1) / 2);
      const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      path.setAttribute('d', 'M ' + x1 + ' ' + y1 + ' C ' + (x1 + curve) + ' ' + y1 + ', ' + (x2 - curve) + ' ' + y2 + ', ' + x2 + ' ' + y2);
      path.setAttribute('fill', 'none');
      path.setAttribute('stroke', '#d4ac6b');
      path.setAttribute('stroke-width', '3');
      path.setAttribute('marker-end', 'url(#flow-arrow)');
      svg.append(path);
    }
  }

  function renderCanvas(canvas, draft, story) {
    canvas.replaceChildren();
    const width = Math.max(920, ...draft.nodes.map(item => Number(item.x || 0) + 250));
    const height = Math.max(520, ...draft.nodes.map(item => Number(item.y || 0) + 180));
    canvas.style.width = width + 'px';
    canvas.style.height = height + 'px';
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.classList.add('flow-links');
    canvas.append(svg);

    for (const flowNode of draft.nodes) {
      const meta = nodeTypes.find(item => item.type === flowNode.type);
      if (!meta) continue;
      const card = element('div', undefined, 'flow-node' + (flowNode.id === selectedNodeId ? ' selected' : ''));
      card.dataset.flowNodeId = flowNode.id;
      card.style.left = Math.max(0, Number(flowNode.x) || 0) + 'px';
      card.style.top = Math.max(0, Number(flowNode.y) || 0) + 'px';
      const head = element('div', labels[flowNode.type] || flowNode.type, 'flow-node-head');
      head.title = 'Drag to move';
      card.append(head);
      const inputPorts = Array.isArray(meta.inputs) ? meta.inputs : (meta.inputs ? ['in'] : []);
      if (inputPorts.length) {
        const row = element('div', undefined, 'flow-input-row');
        for (const socket of inputPorts) {
          const input = element('button', socket, 'flow-port');
          input.type = 'button';
          input.title = 'Connect a flow output to input ' + socket;
          input.dataset.role = 'input';
          input.dataset.nodeId = flowNode.id;
          input.dataset.socket = socket;
          input.onclick = event => { event.stopPropagation(); portClick('input', flowNode.id, socket); };
          row.append(input);
        }
        card.append(row);
      }
      const summary = element('div', nodeSummary(flowNode, story), 'flow-node-summary');
      card.append(summary);
      if (meta.outputs.length) {
        const row = element('div', undefined, 'flow-output-row');
        for (const output of meta.outputs) {
          const button = element('button', output, 'flow-port flow-output-port');
          button.type = 'button';
          button.title = 'Select ' + output + ' output';
          button.dataset.role = 'output';
          button.dataset.nodeId = flowNode.id;
          button.dataset.socket = output;
          button.onclick = event => { event.stopPropagation(); portClick('output', flowNode.id, output); };
          row.append(button);
        }
        card.append(row);
      }
      card.onclick = () => {
        selectedNodeId = flowNode.id;
        renderEditor();
      };
      head.onpointerdown = event => {
        if (event.button !== 0) return;
        event.preventDefault();
        const startX = event.clientX, startY = event.clientY;
        const originX = Number(flowNode.x) || 0, originY = Number(flowNode.y) || 0;
        const move = moveEvent => {
          const x = Math.max(0, originX + moveEvent.clientX - startX);
          const y = Math.max(0, originY + moveEvent.clientY - startY);
          flowNode.x = Math.round(x);
          flowNode.y = Math.round(y);
          card.style.left = x + 'px';
          card.style.top = y + 'px';
          const requiredWidth = Math.max(canvas.scrollWidth, x + 250);
          const requiredHeight = Math.max(canvas.scrollHeight, y + 180);
          canvas.style.width = requiredWidth + 'px';
          canvas.style.height = requiredHeight + 'px';
          drawConnections(canvas, svg, draft);
        };
        const up = () => {
          document.removeEventListener('pointermove', move);
          document.removeEventListener('pointerup', up);
          markChanged('Unsaved flow changes');
        };
        document.addEventListener('pointermove', move);
        document.addEventListener('pointerup', up, { once: true });
      };
      card.onpointerdown = event => {
        if (event.target === card) card.style.zIndex = '2';
      };
      canvas.append(card);
    }
    drawConnections(canvas, svg, draft);
  }

  function nodeSummary(flowNode, story) {
    const data = flowNode.data || {};
    switch (flowNode.type) {
      case 'scene': return (story.scenes || []).find(item => String(item.id) === String(data.sceneId))?.title || 'Choose a scene beat';
      case 'delay': return Number(data.seconds || 0) + ' second(s)';
      case 'branch': return String(data.variable || 'variable') + ' ' + String(data.operator || '==') + ' ' + String(data.value ?? '');
      case 'random_branch': return Number(data.chance ?? 50) + '% success';
      case 'set_variable': return String(data.variable || 'variable') + ' = ' + String(data.value ?? '');
      case 'add_variable': return String(data.variable || 'variable') + ' + ' + String(data.amount ?? 0);
      case 'subtract_variable': return String(data.variable || 'variable') + ' − ' + String(data.amount ?? 0);
      case 'objective': return String(data.text || 'Configure objective text');
      case 'wait_objective': return 'Waits for completed or failed';
      case 'wait_area': case 'wait_all_in_area': case 'wait_area_empty': return (storyteller.getState()?.areas || []).find(area => String(area.id) === String(data.areaId))?.label || 'Choose a saved area';
      case 'check_player_count': return 'Players ' + String(data.operator || '>=') + ' ' + Number(data.count ?? 1);
      case 'check_job': return (storyteller.getState()?.playerActions?.jobs || []).find(job => job.name === data.jobName)?.label || 'Choose an allowlisted VORP job';
      case 'check_entity_alive': return storyteller.getState()?.world?.targets?.find(target => String(target.id) === String(data.targetId))?.label || 'Choose a registered entity target';
      case 'complete_objective': return 'Mark the active objective complete';
      case 'fail_objective': return 'Mark the active objective failed';
      case 'and_node': return 'Wait for both A and B';
      case 'or_node': return 'Continue on the first input';
      case 'not_node': return 'Passes execution through unchanged';
      case 'play_cutscene': return (story.scenes || []).find(scene => String(scene.id) === String(data.sceneId))?.title || 'Choose a scene with a camera rail';
      case 'wait_cutscene': return 'Waits until playback completes or is stopped';
      case 'stop_cutscene': return 'Stops playback for the session audience';
      case 'spawn_npc': case 'spawn_npc_group': return Number(data.count || 1) + ' × ' + String(data.model || 'Choose allowlisted NPC');
      case 'spawn_prop': return String(data.model || 'Choose allowlisted prop');
      case 'remove_npc': return 'Removes Arachnid spawned NPCs';
      case 'delete_prop': return 'Removes Arachnid spawned props';
      case 'wait_npc_death': return 'Waits until any tracked NPC dies';
      case 'wait_npcs_dead': return 'Waits until all tracked NPCs are dead';
      case 'make_npc_hostile': return 'Targets a connected session participant';
      case 'set_npc_target': return data.target === 'all' ? 'Distribute targets across audience players' : 'Choose one random audience player';
      case 'patrol_route': return (data.markerIds || []).length + ' patrol waypoints · ' + Number(data.speed || 1) + ' pace';
      case 'stop_patrol': return 'Stops movement and combat orders for tracked NPCs';
      case 'door_open': case 'door_close': case 'door_lock': case 'door_unlock': case 'entity_enable': case 'entity_disable': case 'trigger_entity':
        return storyteller.getState()?.world?.targets?.find(target => String(target.id) === String(data.targetId))?.label || 'Choose a registered target';
      case 'play_sound': case 'stop_sound': return storyteller.getState()?.effects?.sounds?.find(sound => sound.id === data.soundId)?.label || 'Choose an allowlisted sound';
      case 'screen_fade': return 'Fade ' + String(data.direction || 'out') + ' over ' + Number(data.duration || 0) + 's';
      case 'announcement': case 'subtitle': return String(data.text || 'Configure effect text');
      case 'screen_shake': return 'Amplitude ' + Number(data.amplitude || 0) + ' · ' + Number(data.duration || 0) + 's';
      case 'send_message': return String(data.message || 'Configure message text');
      case 'freeze_players': case 'unfreeze_players': case 'strip_all_weapons': case 'kill_players': case 'respawn_players': return data.target === 'random' ? 'One random participant' : 'All participants';
      case 'set_health': return 'Health ' + Number(data.health ?? 100) + ' · ' + (data.target === 'random' ? 'random' : 'all');
      case 'set_armor': return 'Armor ' + Number(data.armor ?? 0) + ' · ' + (data.target === 'random' ? 'random' : 'all');
      case 'give_weapon': return 'Give ' + String(data.weapon || 'Choose allowlisted weapon') + ' · ' + Number(data.ammo ?? 0) + ' ammo';
      case 'strip_weapon': return 'Remove ' + String(data.weapon || 'Choose allowlisted weapon');
      case 'teleport_players': return (story.teleports || []).find(marker => String(marker.id) === String(data.markerId))?.label || 'Choose a teleport marker';
      case 'change_job': return (storyteller.getState()?.playerActions?.jobs || []).find(job => job.name === data.jobName)?.label || 'Choose an allowlisted VORP job';
      case 'start': return 'Flow entry point';
      case 'end': return 'Finish live session';
      default: return '';
    }
  }

  function setData(flowNode, key, value) {
    flowNode.data = flowNode.data || {};
    flowNode.data[key] = value;
    markChanged('Unsaved flow changes');
    const card = document.querySelector('[data-flow-node-id="' + CSS.escape(flowNode.id) + '"] .flow-node-summary');
    if (card) card.textContent = nodeSummary(flowNode, currentStory());
  }

  function field(label, control) {
    const wrapper = element('label', label, 'flow-field');
    wrapper.append(control);
    return wrapper;
  }

  function inputControl(value, type, min, max, step) {
    const control = document.createElement('input');
    control.type = type || 'text';
    control.value = value == null ? '' : String(value);
    if (min != null) control.min = String(min);
    if (max != null) control.max = String(max);
    if (step != null) control.step = String(step);
    return control;
  }

  function selectControl(options, value) {
    const control = document.createElement('select');
    for (const optionData of options) {
      const option = element('option', optionData.label);
      option.value = String(optionData.value);
      control.append(option);
    }
    control.value = value == null ? '' : String(value);
    return control;
  }

  function renderValueEditor(editor, flowNode, story, branch) {
    const data = flowNode.data || (flowNode.data = {});
    const typeControl = selectControl([
      { value: 'number', label: 'Number' },
      { value: 'text', label: 'Text' },
      { value: 'boolean', label: 'True / false' }
    ], data.valueType || 'text');
    editor.append(field('Value type', typeControl));
    const valueType = data.valueType || 'text';
    if (valueType === 'boolean') {
      const value = selectControl([{ value: 'true', label: 'True' }, { value: 'false', label: 'False' }], String(data.value ?? true));
      value.onchange = () => setData(flowNode, 'value', value.value === 'true');
      editor.append(field(branch ? 'Compare value' : 'Value', value));
    } else {
      const value = inputControl(data.value ?? (valueType === 'number' ? 0 : ''), valueType === 'number' ? 'number' : 'text', valueType === 'number' ? -1000000000 : null, valueType === 'number' ? 1000000000 : null, valueType === 'number' ? 'any' : null);
      value.oninput = () => setData(flowNode, 'value', valueType === 'number' ? (value.value === '' ? '' : Number(value.value)) : value.value);
      editor.append(field(branch ? 'Compare value' : 'Value', value));
    }
    typeControl.onchange = () => {
      const next = typeControl.value;
      flowNode.data.valueType = next;
      flowNode.data.value = next === 'boolean' ? true : next === 'number' ? 0 : '';
      if (branch && ['>', '<', '>=', '<='].includes(flowNode.data.operator) && next !== 'number') flowNode.data.operator = '==';
      markChanged('Unsaved flow changes');
      renderEditor();
    };
  }

  function renderSettings(editor, flowNode, story) {
    const data = flowNode.data || (flowNode.data = {});
    const state = storyteller.getState() || {};
    const textField = (label, key, placeholder, maxLength) => {
      const control = document.createElement('textarea');
      control.value = data[key] || '';
      control.placeholder = placeholder || '';
      if (maxLength) control.maxLength = maxLength;
      control.oninput = () => setData(flowNode, key, control.value);
      editor.append(field(label, control));
    };
    const numberField = (label, key, value, min, max, step = 'any') => {
      const control = inputControl(data[key] ?? value, 'number', min, max, step);
      control.oninput = () => setData(flowNode, key, control.value === '' ? '' : Number(control.value));
      editor.append(field(label, control));
    };
    const variableField = () => {
      const control = inputControl(data.variable || '', 'text');
      control.maxLength = 32;
      control.placeholder = 'Variable name';
      control.oninput = () => setData(flowNode, 'variable', control.value);
      editor.append(field('Variable name', control));
    };
    const spawnMarkers = story.spawnPoints || [];
    const spawnMarkerField = (kind, key) => {
      const markers = spawnMarkers.filter(marker => marker.kind === kind);
      const control = selectControl([{ value: '', label: 'Choose a saved ' + kind + ' marker' }, ...markers.map(marker => ({ value: marker.id, label: marker.label }))], data[key]);
      control.onchange = () => setData(flowNode, key, control.value ? Number(control.value) : null);
      editor.append(field('Spawn marker', control));
    };
    const modelField = (kind) => {
      const models = storyteller.getState()?.encounters?.models?.[kind] || [];
      const control = selectControl([{ value: '', label: 'Choose an allowlisted model' }, ...models.map(model => ({ value: model.name, label: model.label }))], data.model);
      control.onchange = () => setData(flowNode, 'model', control.value);
      editor.append(field(kind === 'ped' ? 'NPC model' : 'Prop model', control));
      if (!models.length) editor.append(element('p', 'The server owner must add models to Config.Encounters.' + (kind === 'ped' ? 'pedModels' : 'propModels') + '.', 'muted'));
    };

    if (flowNode.type === 'scene') {
      const options = [{ value: '', label: 'Choose a scene beat' }, ...(story.scenes || []).map(scene => ({ value: scene.id, label: scene.title }))];
      const control = selectControl(options, data.sceneId);
      control.onchange = () => setData(flowNode, 'sceneId', control.value ? Number(control.value) : null);
      editor.append(field('Scene beat', control));
    } else if (flowNode.type === 'delay') {
      numberField('Delay in seconds', 'seconds', 3, 0, Number(storyteller.getState()?.flowLimits?.maxDelaySeconds || 3600), '0.1');
    } else if (flowNode.type === 'branch') {
      variableField();
      const op = selectControl(['==', '!=', '>', '<', '>=', '<='].map(value => ({ value, label: value })), data.operator || '==');
      op.onchange = () => setData(flowNode, 'operator', op.value);
      editor.append(field('Operator', op));
      renderValueEditor(editor, flowNode, story, true);
    } else if (flowNode.type === 'random_branch') {
      numberField('Success chance (%)', 'chance', 50, 0, 100, '1');
    } else if (flowNode.type === 'set_variable') {
      variableField();
      renderValueEditor(editor, flowNode, story, false);
    } else if (flowNode.type === 'add_variable' || flowNode.type === 'subtract_variable') {
      variableField();
      numberField('Amount', 'amount', 1, -1000000000, 1000000000, 'any');
    } else if (flowNode.type === 'objective') {
      textField('Player-facing objective', 'text', 'Objective shown to the audience', 1000);
    } else if (['wait_area', 'wait_all_in_area', 'wait_area_empty'].includes(flowNode.type)) {
      const areas = storyteller.getState()?.areas || [];
      const options = [{ value: '', label: 'Choose a saved area' }, ...areas.map(area => ({ value: area.id, label: area.label + ' · ' + area.shape }))];
      const control = selectControl(options, data.areaId);
      control.onchange = () => setData(flowNode, 'areaId', control.value ? Number(control.value) : null);
      editor.append(field('Saved area', control));
      const text = flowNode.type === 'wait_all_in_area' ? 'Waits until every connected session participant is in the area.' : flowNode.type === 'wait_area_empty' ? 'Waits until no connected session participant remains in the area.' : 'Waits until any connected session participant enters the area.';
      editor.append(element('p', text, 'muted'));
    } else if (flowNode.type === 'check_player_count') {
      const operator = selectControl(['==', '!=', '>', '<', '>=', '<='].map(value => ({ value, label: value })), data.operator || '>=');
      operator.onchange = () => setData(flowNode, 'operator', operator.value);
      editor.append(field('Comparison', operator));
      numberField('Player count', 'count', 1, 0, Number(state.flowLimits?.maxParticipants || 64), '1');
    } else if (flowNode.type === 'check_job') {
      const jobs = storyteller.getState()?.playerActions?.jobs || [];
      const control = selectControl([{ value: '', label: 'Choose an allowlisted VORP job' }, ...jobs.map(job => ({ value: job.name, label: job.label }))], data.jobName);
      control.onchange = () => setData(flowNode, 'jobName', control.value);
      editor.append(field('Job present in audience', control));
      if (!jobs.length) editor.append(element('p', 'The server owner must configure VORP job allowlist entries before this check can be used.', 'muted'));
    } else if (flowNode.type === 'check_entity_alive') {
      const targets = storyteller.getState()?.world?.targets || [];
      const control = selectControl([{ value: '', label: 'Choose a registered entity target' }, ...targets.map(target => ({ value: target.id, label: target.label }))], data.targetId);
      control.onchange = () => setData(flowNode, 'targetId', control.value);
      editor.append(field('Registered world target', control));
      editor.append(element('p', 'Reads only the owner-configured target state. Unknown runtime entity IDs are rejected.', 'muted'));
    } else if (worldNodeActions.has(flowNode.type)) {
      const action = worldNodeActions.get(flowNode.type);
      const targets = (state.world?.targets || []).filter(target => target.actions?.[action]);
      const control = selectControl([{ value: '', label: 'Choose a target that allows ' + action }, ...targets.map(target => ({ value: target.id, label: target.label }))], data.targetId);
      control.onchange = () => setData(flowNode, 'targetId', control.value);
      editor.append(field('Registered world target', control));
      editor.append(element('p', 'The server owner defines the target, permitted operations, and session-end restore policy in Config.World.targets.', 'muted'));
    } else if (flowNode.type === 'play_sound' || flowNode.type === 'stop_sound') {
      const sounds = state.effects?.sounds || [];
      const control = selectControl([{ value: '', label: 'Choose an allowlisted sound' }, ...sounds.map(sound => ({ value: sound.id, label: sound.label }))], data.soundId);
      control.onchange = () => setData(flowNode, 'soundId', control.value);
      editor.append(field('Sound', control));
      if (flowNode.type === 'play_sound') {
        numberField('Volume', 'volume', 1, 0, Number(state.effects?.maxVolume || 1), '0.05');
        numberField('Pitch', 'pitch', 100, Number(state.effects?.minPitch || 50), Number(state.effects?.maxPitch || 150), '1');
      }
    } else if (flowNode.type === 'screen_fade') {
      const direction = selectControl([{ value: 'out', label: 'Fade out' }, { value: 'in', label: 'Fade in' }], data.direction || 'out');
      direction.onchange = () => setData(flowNode, 'direction', direction.value);
      editor.append(field('Direction', direction));
      numberField('Duration in seconds', 'duration', 1, 0, Number(state.effects?.maxDurationSeconds || 30), '0.1');
    } else if (flowNode.type === 'announcement' || flowNode.type === 'subtitle') {
      textField(flowNode.type === 'announcement' ? 'Announcement text' : 'Subtitle text', 'text', 'Player-facing text', Number(state.effects?.maxMessageLength || 1000));
      numberField('Display duration in seconds', 'duration', 5, 1, Number(state.effects?.maxDurationSeconds || 30), '0.1');
    } else if (flowNode.type === 'screen_shake') {
      numberField('Amplitude', 'amplitude', 1, 0, Number(state.effects?.maxShakeAmplitude || 10), '0.1');
      numberField('Frequency', 'frequency', 1, 0, Number(state.effects?.maxShakeFrequency || 10), '0.1');
      numberField('Duration in seconds', 'duration', 2, 1, Number(state.effects?.maxDurationSeconds || 30), '0.1');
    } else if (flowNode.type === 'complete_objective' || flowNode.type === 'fail_objective') {
      editor.append(element('p', flowNode.type === 'complete_objective' ? 'Marks the active objective complete.' : 'Marks the active objective failed.', 'muted'));
    } else if (flowNode.type === 'and_node' || flowNode.type === 'or_node') {
      editor.append(element('p', flowNode.type === 'and_node' ? 'AND waits until inputs A and B have both fired.' : 'OR continues after the first of inputs A or B fires.', 'muted'));
    } else if (flowNode.type === 'not_node') {
      editor.append(element('p', 'GMod compatible pass-through node. Execution continues without negating or changing data.', 'muted'));
    } else if (flowNode.type === 'spawn_npc' || flowNode.type === 'spawn_npc_group') {
      modelField('ped'); spawnMarkerField('npc', 'spawnPointId');
      numberField('NPC health', 'health', 150, 1, Number(state.encounters?.maxNpcHealth || 1000), '1');
      if (flowNode.type === 'spawn_npc_group') numberField('Group count', 'count', 3, 1, Number(state.encounters?.maxGroupCount || 12), '1');
    } else if (flowNode.type === 'spawn_prop') {
      modelField('prop'); spawnMarkerField('prop', 'spawnPointId');
    } else if (flowNode.type === 'set_npc_target') {
      const control = selectControl([{ value: 'random', label: 'One random connected participant' }, { value: 'all', label: 'Distribute targets across participants' }], data.target || 'random');
      control.onchange = () => setData(flowNode, 'target', control.value);
      editor.append(field('Target selection', control));
    } else if (flowNode.type === 'patrol_route') {
      const markers = spawnMarkers.filter(marker => marker.kind === 'patrol');
      let route = Array.isArray(data.markerIds) ? data.markerIds.map(Number).filter(id => markers.some(marker => Number(marker.id) === id)) : [];
      const control = selectControl([{ value: '', label: 'Choose a patrol waypoint' }, ...markers.map(marker => ({ value: marker.id, label: marker.label }))], '');
      const addWaypoint = element('button', 'Add waypoint'); addWaypoint.type = 'button';
      const routeList = element('div', undefined, 'flow-route-list');
      const updateRoute = next => { route = next; setData(flowNode, 'markerIds', route.slice()); renderRoute(); };
      const renderRoute = () => {
        routeList.replaceChildren();
        if (!route.length) routeList.append(element('p', 'Add at least two waypoints in the order NPCs should visit them.', 'muted'));
        route.forEach((markerId, index) => {
          const marker = markers.find(item => Number(item.id) === markerId);
          if (!marker) return;
          const row = element('div', undefined, 'flow-route-row');
          row.append(element('span', (index + 1) + '. ' + marker.label));
          const up = element('button', '↑'); up.type = 'button'; up.disabled = index === 0;
          up.onclick = () => { const next = route.slice(); [next[index - 1], next[index]] = [next[index], next[index - 1]]; updateRoute(next); };
          const down = element('button', '↓'); down.type = 'button'; down.disabled = index === route.length - 1;
          down.onclick = () => { const next = route.slice(); [next[index], next[index + 1]] = [next[index + 1], next[index]]; updateRoute(next); };
          const remove = element('button', 'Remove'); remove.type = 'button';
          remove.onclick = () => updateRoute(route.filter((_, routeIndex) => routeIndex !== index));
          row.append(up, down, remove); routeList.append(row);
        });
      };
      addWaypoint.onclick = () => {
        const markerId = Number(control.value);
        if (markerId && markers.some(marker => Number(marker.id) === markerId)) updateRoute([...route, markerId]);
      };
      editor.append(field('Add waypoint to ordered route', control), addWaypoint, routeList);
      renderRoute();
      numberField('Movement pace', 'speed', Number(state.encounters?.defaultPatrolSpeed || 1), Number(state.encounters?.minPatrolSpeed || 0.5), Number(state.encounters?.maxPatrolSpeed || 3), '0.1');
      numberField('Seconds at each waypoint', 'waitSeconds', 3, 0, Number(state.encounters?.maxPatrolWaitSeconds || 300), '1');
    } else if (flowNode.type === 'stop_patrol') {
      editor.append(element('p', 'Stops patrol and combat orders for every NPC tracked by the active session.', 'muted'));
    } else if (flowNode.type === 'remove_npc' || flowNode.type === 'delete_prop' || flowNode.type === 'make_npc_hostile' || flowNode.type === 'wait_npc_death' || flowNode.type === 'wait_npcs_dead') {
      const messages = {
        remove_npc: 'Removes all NPCs spawned by Arachnid in this session.',
        delete_prop: 'Removes all props spawned by Arachnid in this session.',
        make_npc_hostile: 'Sends spawned NPCs to attack a connected session participant.',
        wait_npc_death: 'Waits indefinitely until any tracked NPC dies.',
        wait_npcs_dead: 'Waits indefinitely until all tracked NPCs are dead.'
      };
      editor.append(element('p', messages[flowNode.type], 'muted'));
    } else if (flowNode.type === 'wait_objective') {
      editor.append(element('p', 'Waits without a timeout until the active objective is marked completed or failed.', 'muted'));
    } else if (flowNode.type === 'play_cutscene') {
      const scenes = (story.scenes || []).filter(scene => (scene.camera_points || []).length > 0);
      const options = [{ value: '', label: 'Choose a scene with a camera rail' }, ...scenes.map(scene => ({ value: scene.id, label: scene.title }))];
      const control = selectControl(options, data.sceneId);
      control.onchange = () => setData(flowNode, 'sceneId', control.value ? Number(control.value) : null);
      editor.append(field('Scene camera rail', control));
    } else if (flowNode.type === 'wait_cutscene') {
      editor.append(element('p', 'Waits without a timeout while the audience watches. Looping rails wait until the GM stops playback.', 'muted'));
    } else if (flowNode.type === 'stop_cutscene') {
      editor.append(element('p', 'Stops the current audience cutscene and restores local presentation state.', 'muted'));
    } else if (flowActionSettings.has(flowNode.type)) {
      const actionConfig = storyteller.getState()?.playerActions || {};
      const target = selectControl([
        { value: 'all', label: 'All connected session participants' },
        { value: 'random', label: 'One random connected participant' }
      ], data.target || 'all');
      target.onchange = () => setData(flowNode, 'target', target.value);
      editor.append(field('Target', target));
      if (flowNode.type === 'send_message') {
        const control = document.createElement('textarea');
        control.value = data.message || '';
        control.maxLength = Number(actionConfig.maxMessageLength || 1000);
        control.placeholder = 'Message shown to each target';
        control.oninput = () => setData(flowNode, 'message', control.value);
        editor.append(field('Message', control));
      } else if (flowNode.type === 'set_health') {
        numberField('Health', 'health', 100, 1, Number(actionConfig.maxHealth || 500), '1');
      } else if (flowNode.type === 'set_armor') {
        numberField('Armor', 'armor', 0, 0, Number(actionConfig.maxArmor || 100), '1');
      } else if (flowNode.type === 'give_weapon' || flowNode.type === 'strip_weapon') {
        const weapons = actionConfig.weapons || [];
        const options = [{ value: '', label: 'Choose an owner-allowlisted weapon' }, ...weapons.map(weapon => ({ value: weapon.name, label: weapon.label }))];
        const control = selectControl(options, data.weapon);
        control.onchange = () => {
          setData(flowNode, 'weapon', control.value);
          if (flowNode.type === 'give_weapon') {
            const selectedWeapon = weapons.find(weapon => weapon.name === control.value);
            setData(flowNode, 'ammo', selectedWeapon?.defaultAmmo ?? 0);
            renderEditor();
          }
        };
        editor.append(field('Weapon', control));
        if (flowNode.type === 'give_weapon') {
          const selectedWeapon = weapons.find(weapon => weapon.name === data.weapon);
          numberField('Ammunition', 'ammo', selectedWeapon?.defaultAmmo ?? 0, 0, selectedWeapon?.maxAmmo ?? Number(actionConfig.maxAmmo || 1000), '1');
        }
        if (!weapons.length) editor.append(element('p', 'The server owner must configure a weapon allowlist before this node can run.', 'muted'));
      } else if (flowNode.type === 'teleport_players') {
        const markers = story.teleports || [];
        const control = selectControl([{ value: '', label: 'Choose a saved teleport marker' }, ...markers.map(marker => ({ value: marker.id, label: marker.label }))], data.markerId);
        control.onchange = () => setData(flowNode, 'markerId', control.value ? Number(control.value) : null);
        editor.append(field('Destination marker', control));
        if (!markers.length) editor.append(element('p', 'Create a per-story teleport marker below first.', 'muted'));
      } else if (flowNode.type === 'change_job') {
        const jobs = actionConfig.jobs || [];
        const selectedJob = jobs.find(job => job.name === data.jobName);
        const jobControl = selectControl([{ value: '', label: 'Choose an owner-allowlisted job' }, ...jobs.map(job => ({ value: job.name, label: job.label }))], data.jobName);
        jobControl.onchange = () => {
          const nextJob = jobs.find(job => job.name === jobControl.value);
          flowNode.data.jobName = jobControl.value;
          flowNode.data.grade = nextJob?.grades?.[0] ?? 0;
          markChanged('Unsaved flow changes');
          renderEditor();
        };
        editor.append(field('VORP active job', jobControl));
        const gradeControl = selectControl((selectedJob?.grades || []).map(grade => ({ value: grade, label: 'Grade ' + grade })), data.grade);
        gradeControl.onchange = () => setData(flowNode, 'grade', Number(gradeControl.value));
        editor.append(field('Job grade', gradeControl));
        if (!jobs.length) editor.append(element('p', 'The server owner must configure an allowed VORP job and grades.', 'muted'));
      } else {
        editor.append(element('p', 'This action runs only when enabled in the server configuration and is limited to this session audience.', 'muted'));
      }
      if (actionConfig.enabled && actionConfig.enabled[flowActionSettings.get(flowNode.type)] === false) {
        editor.append(element('p', 'This action is currently disabled by the server owner.', 'muted'));
      }
    } else if (flowNode.type === 'start' || flowNode.type === 'end') {
      editor.append(element('p', flowNode.type === 'start' ? 'The graph must have one Start node.' : 'End stops the live session.', 'muted'));
    }
  }

  function renderTeleportManager(panel, story) {
    const markers = story.teleports || [];
    if (editingTeleportId != null && !markers.some(marker => String(marker.id) === String(editingTeleportId))) editingTeleportId = null;
    const selected = markers.find(marker => String(marker.id) === String(editingTeleportId));
    const section = element('div', undefined, 'card flow-teleport-manager');
    section.append(element('h4', 'Teleport markers'));
    section.append(element('p', 'Create story-specific destinations at your server-verified in-game position and heading.', 'muted'));
    const create = element('button', 'New teleport marker');
    create.type = 'button';
    create.onclick = () => { editingTeleportId = null; renderEditor(); };
    section.append(create);

    const form = element('div', undefined, 'flow-teleport-form');
    const label = inputControl(selected?.label || '', 'text');
    label.maxLength = 100;
    label.placeholder = 'Marker name';
    form.append(field('Marker name', label));
    const capture = document.createElement('input');
    capture.type = 'checkbox';
    capture.checked = !selected;
    const captureLabel = element('label', selected ? ' Update saved position to my current location' : ' Capture my current position and heading');
    captureLabel.prepend(capture);
    form.append(captureLabel);
    const save = element('button', selected ? 'Save teleport marker' : 'Create teleport marker');
    save.type = 'button';
    save.onclick = () => {
      if (!label.value.trim()) { label.focus(); return; }
      storyteller.send('teleportSave', {
        storyId: story.id, id: selected?.id, label: label.value, capturePosition: capture.checked
      });
    };
    form.append(save);
    if (selected) {
      const remove = element('button', 'Delete teleport marker', 'danger');
      remove.type = 'button';
      remove.onclick = () => {
        if (!window.confirm('Delete teleport marker “' + selected.label + '”?')) return;
        storyteller.send('teleportDelete', { storyId: story.id, id: selected.id });
        editingTeleportId = null;
      };
      form.append(remove);
    }
    section.append(form);

    if (markers.length) {
      const list = element('div', undefined, 'item-grid');
      for (const marker of markers) {
        const card = element('div', undefined, 'card');
        card.append(element('strong', marker.label));
        card.append(element('p', 'Position: ' + [marker.x, marker.y, marker.z].map(value => Number(value).toFixed(2)).join(', ') + ' · heading ' + Number(marker.heading).toFixed(1) + '°', 'muted'));
        const edit = element('button', String(editingTeleportId) === String(marker.id) ? 'Editing' : 'Edit marker');
        edit.type = 'button';
        edit.onclick = () => { editingTeleportId = marker.id; renderEditor(); };
        card.append(edit);
        list.append(card);
      }
      section.append(list);
    } else {
      section.append(element('p', 'No teleport markers saved for this story.', 'muted'));
    }
    panel.append(section);
  }

  function renderCutsceneManager(panel, story) {
    const state = storyteller.getState() || {};
    const config = state.cutscenes || {};
    const sceneOptions = (story.scenes || []).filter(scene => (scene.camera_points || []).length > 0);
    if (!sceneOptions.some(scene => String(scene.id) === String(cutsceneSceneId))) cutsceneSceneId = sceneOptions[0]?.id ?? null;
    const section = element('div', undefined, 'card flow-cutscene-manager');
    section.append(element('h3', 'Cutscene playback'));
    section.append(element('p', 'Play a saved camera rail locally for preview, or send it to the current session audience.', 'muted'));
    const picker = selectControl([{ value: '', label: 'Choose a scene with a camera rail' }, ...sceneOptions.map(scene => ({ value: scene.id, label: scene.title }))], cutsceneSceneId);
    picker.onchange = () => { cutsceneSceneId = picker.value ? Number(picker.value) : null; renderEditor(); };
    section.append(field('Scene', picker));
    const selectedScene = sceneOptions.find(scene => String(scene.id) === String(picker.value));
    const enabled = config.enabled === true;
    const activeSession = state.session?.state === 'active';
    const liveForStory = activeSession && Number(state.session.story?.id) === Number(story.id);
    const buttons = element('div', undefined, 'flow-toolbar');
    const preview = element('button', 'Preview locally');
    preview.type = 'button'; preview.disabled = !enabled || !selectedScene || activeSession;
    preview.onclick = () => storyteller.send('cutscenePreview', { sceneId: selectedScene.id });
    buttons.append(preview);
    if (!activeSession) {
      const stopPreview = element('button', 'Stop local preview', 'danger');
      stopPreview.type = 'button'; stopPreview.disabled = !enabled;
      stopPreview.onclick = () => storyteller.send('cutscenePreviewStop');
      buttons.append(stopPreview);
    }
    if (liveForStory) {
      const play = element('button', 'Play for session audience');
      play.type = 'button'; play.disabled = !enabled || !selectedScene;
      play.onclick = () => storyteller.send('sessionCutscenePlay', { sceneId: selectedScene.id });
      const activeCutscene = state.session.cutscene;
      if (activeCutscene && !state.session.flow) {
        const toggle = element('button', activeCutscene.paused ? 'Resume audience cutscene' : 'Pause audience cutscene');
        toggle.type = 'button'; toggle.disabled = !enabled;
        toggle.onclick = () => storyteller.send(activeCutscene.paused ? 'sessionCutsceneResume' : 'sessionCutscenePause');
        buttons.append(toggle);
      }
      const stop = element('button', 'Stop audience cutscene', 'danger');
      stop.type = 'button'; stop.disabled = !enabled;
      stop.onclick = () => storyteller.send('sessionCutsceneStop');
      buttons.append(play, stop);
    }
    section.append(buttons);
    if (!enabled) section.append(element('p', 'Playback is disabled. Enable Config.Cutscenes.enabled and grant the cutscenes ACE permission.', 'muted'));
    if (activeSession && !liveForStory) section.append(element('p', 'Another story is live. Manual playback controls are available only for its storyteller.', 'muted'));
    if (!selectedScene) section.append(element('p', 'Add a camera node to a scene before previewing or playing it.', 'muted'));
    if (selectedScene) {
      const current = selectedScene.cutscene_settings || config.defaults || {};
      const draft = { ...current };
      const checkbox = (label, key) => {
        const control = document.createElement('input');
        control.type = 'checkbox'; control.checked = current[key] === true;
        control.onchange = () => { draft[key] = control.checked; };
        const wrapper = element('label', ' ' + label); wrapper.prepend(control); section.append(wrapper);
      };
      checkbox('Freeze players during playback', 'freezePlayers');
      checkbox('Hide HUD during playback', 'hideHud');
      checkbox('Show letterbox bars', 'letterbox');
      checkbox('Loop until stopped', 'loop');
      for (const [key, label, fallback, min, max] of [
        ['fadeIn', 'Fade in seconds', 0, 0, Number(config.maxFadeSeconds || 30)],
        ['fadeOut', 'Fade out seconds', 0, 0, Number(config.maxFadeSeconds || 30)],
        ['defaultFov', 'Default FOV', 75, Number(config.minFov || 20), Number(config.maxFov || 120)]
      ]) {
        const control = inputControl(current[key] ?? fallback, 'number', min, max, '0.1');
        control.oninput = () => { draft[key] = control.value === '' ? '' : Number(control.value); };
        section.append(field(label, control));
      }
      const save = element('button', 'Save cutscene settings');
      save.type = 'button';
      save.onclick = () => storyteller.send('sceneCutsceneSettingsSave', { sceneId: selectedScene.id, settings: draft });
      section.append(save);
    }
    panel.append(section);
  }

  let rtsCanvas = null;
  let rtsRoster = null;
  let rtsSelectionSummary = null;
  let rtsWeaponPanel = null;
  let rtsTargetPicker = null;
  let rtsSpeedControl = null;
  let rtsDwellControl = null;
  let rtsWaypointPicker = null;
  let rtsRouteList = null;
  let rtsSnapshot = null;
  let rtsView = null;
  let rtsPan = null;

  function closeRtsCommandView() {
    if (rtsSnapshotTimer) clearInterval(rtsSnapshotTimer);
    rtsSnapshotTimer = null;
    rtsOverlay?.remove();
    rtsOverlay = null;
    rtsStoryId = null;
    rtsStory = null;
    rtsCanvas = rtsRoster = rtsSelectionSummary = rtsWeaponPanel = null;
    rtsTargetPicker = rtsSpeedControl = rtsDwellControl = rtsWaypointPicker = rtsRouteList = null;
    rtsView = rtsPan = null;
    selectedRtsUnits.clear();
    rtsPatrolRoute = [];
  }

  function sendRtsCommand(action, extra = {}) {
    const ids = [...selectedRtsUnits];
    if (!ids.length) return;
    storyteller.send('sessionEncounterAction', { action, npcIds: ids, ...extra });
  }

  function openRtsCommandView(story) {
    if (!story?.id) return;
    if (rtsOverlay && Number(rtsStoryId) === Number(story.id)) return;
    closeRtsCommandView();
    rtsStoryId = Number(story.id);
    rtsStory = story;
    selectedRtsUnits.clear();
    rtsPatrolRoute = [];
    rtsSnapshot = null;
    const currentState = storyteller.getState();
    if (currentState) currentState.rtsSnapshot = null;
    rtsOverlay = element('div', undefined, 'rts-overlay');
    rtsOverlay.id = 'npc-rts-command-view';
    const shell = element('div', undefined, 'rts-shell');
    const header = element('header', undefined, 'rts-header');
    const heading = element('div');
    heading.append(element('small', 'ARACHNID STORYTELLER · LIVE TACTICAL CONTROL'), element('h2', 'NPC RTS COMMAND VIEW'), element('p', 'Select Arachnid NPC units, then issue orders from the tactical board and command bar.', 'muted'));
    const close = element('button', 'Close RTS view'); close.type = 'button'; close.onclick = closeRtsCommandView;
    header.append(heading, close);
    const layout = element('div', undefined, 'rts-layout');
    const boardPanel = element('section', undefined, 'rts-board-panel');
    const boardHeader = element('div', undefined, 'rts-board-heading');
    boardHeader.append(element('h3', 'Tactical board'), element('span', 'Left-click units to select · Right-click ground to move · Shift + right-click to move fast', 'muted'));
    const mapControls = element('div', undefined, 'rts-map-controls');
    const zoomOut = element('button', '−'); zoomOut.type = 'button'; zoomOut.title = 'Zoom out'; zoomOut.onclick = () => changeRtsZoom(1 / 1.2);
    const zoomIn = element('button', '+'); zoomIn.type = 'button'; zoomIn.title = 'Zoom in'; zoomIn.onclick = () => changeRtsZoom(1.2);
    const fitBoard = element('button', 'Fit units'); fitBoard.type = 'button'; fitBoard.onclick = fitRtsBoard;
    mapControls.append(zoomOut, zoomIn, fitBoard);
    boardHeader.append(mapControls);
    rtsCanvas = document.createElement('canvas'); rtsCanvas.className = 'rts-board'; rtsCanvas.width = 1100; rtsCanvas.height = 650;
    rtsCanvas.addEventListener('contextmenu', event => event.preventDefault());
    rtsCanvas.addEventListener('click', event => handleRtsBoardClick(event, false));
    rtsCanvas.addEventListener('contextmenu', event => { event.preventDefault(); handleRtsBoardClick(event, true); });
    rtsCanvas.addEventListener('wheel', event => {
      event.preventDefault();
      const rect = rtsCanvas.getBoundingClientRect();
      changeRtsZoom(event.deltaY < 0 ? 1.15 : 1 / 1.15, (event.clientX - rect.left) * (rtsCanvas.width / rect.width), (event.clientY - rect.top) * (rtsCanvas.height / rect.height));
    }, { passive: false });
    rtsCanvas.addEventListener('pointerdown', event => {
      if (event.button !== 1 || !rtsView) return;
      event.preventDefault(); rtsCanvas.setPointerCapture(event.pointerId);
      rtsPan = { pointerId: event.pointerId, x: event.clientX, y: event.clientY };
    });
    rtsCanvas.addEventListener('pointermove', event => {
      if (!rtsPan || rtsPan.pointerId !== event.pointerId || !rtsView) return;
      const rect = rtsCanvas.getBoundingClientRect();
      const dx = (event.clientX - rtsPan.x) * (rtsCanvas.width / rect.width);
      const dy = (event.clientY - rtsPan.y) * (rtsCanvas.height / rect.height);
      rtsView.centerX -= dx / rtsView.scale; rtsView.centerY += dy / rtsView.scale;
      rtsPan.x = event.clientX; rtsPan.y = event.clientY;
      drawRtsBoard(rtsSnapshot);
    });
    rtsCanvas.addEventListener('pointerup', event => { if (rtsPan?.pointerId === event.pointerId) rtsPan = null; });
    rtsCanvas.addEventListener('pointercancel', () => { rtsPan = null; });
    rtsSelectionSummary = element('p', 'No NPCs selected.', 'muted');
    boardPanel.append(boardHeader, rtsCanvas, element('p', 'NPCs: red · selected units: gold · patrol waypoints: diamonds · audience players: blue', 'muted'), rtsSelectionSummary);
    const rosterPanel = element('aside', undefined, 'rts-roster-panel');
    rosterPanel.append(element('h3', 'Session units'));
    rtsRoster = element('div', undefined, 'rts-roster');
    rosterPanel.append(rtsRoster);
    layout.append(boardPanel, rosterPanel);

    const commandBar = element('section', undefined, 'rts-command-bar');
    const selectionControls = element('div', undefined, 'rts-command-section');
    selectionControls.append(element('h3', 'Selection'));
    const selectAll = element('button', 'Select all living NPCs'); selectAll.type = 'button';
    selectAll.onclick = () => { for (const unit of rtsSnapshot?.units || []) if (unit.alive) selectedRtsUnits.add(String(unit.id)); updateRtsDisplay(); };
    const clearSelection = element('button', 'Clear selection'); clearSelection.type = 'button';
    clearSelection.onclick = () => { selectedRtsUnits.clear(); updateRtsDisplay(); };
    selectionControls.append(selectAll, clearSelection);

    const movement = element('div', undefined, 'rts-command-section');
    movement.append(element('h3', 'Movement orders'));
    rtsWaypointPicker = selectControl([{ value: '', label: 'Choose saved waypoint' }, ...(story.spawnPoints || []).filter(point => point.kind === 'patrol').map(point => ({ value: point.id, label: point.label }))], '');
    rtsSpeedControl = inputControl(Number(storyteller.getState()?.encounters?.defaultPatrolSpeed || 1), 'number', Number(storyteller.getState()?.encounters?.minPatrolSpeed || 0.5), Number(storyteller.getState()?.encounters?.maxPatrolSpeed || 3), '0.1');
    rtsDwellControl = inputControl(3, 'number', 0, Number(storyteller.getState()?.encounters?.maxPatrolWaitSeconds || 300), '1');
    const moveButton = element('button', 'Move selected to waypoint'); moveButton.type = 'button';
    moveButton.onclick = () => rtsWaypointPicker.value && sendRtsCommand('rts_move', { markerId: Number(rtsWaypointPicker.value), speed: Number(rtsSpeedControl.value) });
    const fastMoveButton = element('button', 'Fast move to waypoint'); fastMoveButton.type = 'button';
    fastMoveButton.onclick = () => rtsWaypointPicker.value && sendRtsCommand('rts_move', { markerId: Number(rtsWaypointPicker.value), speed: Number(storyteller.getState()?.encounters?.maxPatrolSpeed || rtsSpeedControl.max) });
    const patrolButton = element('button', 'Patrol selected route'); patrolButton.type = 'button';
    patrolButton.onclick = () => sendRtsCommand('rts_patrol', { markerIds: rtsPatrolRoute.slice(), speed: Number(rtsSpeedControl.value), waitSeconds: Number(rtsDwellControl.value) });
    const stopButton = element('button', 'Stop / hold selected', 'danger'); stopButton.type = 'button';
    stopButton.onclick = () => sendRtsCommand('rts_stop');
    movement.append(field('Single move target', rtsWaypointPicker), field('Movement pace', rtsSpeedControl), field('Patrol dwell seconds', rtsDwellControl), moveButton, fastMoveButton);
    const routePicker = selectControl([{ value: '', label: 'Add route waypoint' }, ...(story.spawnPoints || []).filter(point => point.kind === 'patrol').map(point => ({ value: point.id, label: point.label }))], '');
    const addRoute = element('button', 'Add waypoint'); addRoute.type = 'button';
    rtsRouteList = element('div', undefined, 'flow-route-list');
    addRoute.onclick = () => { const id = Number(routePicker.value); if (id && !rtsPatrolRoute.includes(id)) { rtsPatrolRoute.push(id); renderRtsRouteList(); } };
    movement.append(field('Ordered patrol route', routePicker), addRoute, rtsRouteList, patrolButton, stopButton);

    const combat = element('div', undefined, 'rts-command-section');
    combat.append(element('h3', 'Engagement'));
    rtsTargetPicker = selectControl([{ value: '', label: 'Choose session participant' }, ...(rtsSnapshot?.players || []).map(player => ({ value: player.id, label: player.name + ' (#' + player.id + ')' }))], '');
    const targetButton = element('button', 'Attack selected participant'); targetButton.type = 'button';
    targetButton.onclick = () => rtsTargetPicker.value && sendRtsCommand('rts_target', { targetPlayerId: Number(rtsTargetPicker.value) });
    const stances = element('div', undefined, 'rts-stances');
    for (const [stance, label, hotkey] of [['fire_at_will', 'Fire at Will · F', 'F'], ['return_fire', 'Return Fire · Z', 'Z'], ['hold_fire', 'Hold Fire · H', 'H']]) {
      const button = element('button', label); button.type = 'button'; button.dataset.stance = stance;
      button.onclick = () => sendRtsCommand('rts_stance', { stance });
      stances.append(button);
    }
    combat.append(field('Target', rtsTargetPicker), targetButton, stances, element('h4', 'Configured weapons'), element('div', undefined, 'muted'));
    rtsWeaponPanel = combat.lastElementChild;
    const weaponInfo = element('p', 'Weapon toggles appear for weapons configured on every selected NPC.', 'muted');
    combat.append(weaponInfo);
    commandBar.append(selectionControls, movement, combat);
    const help = element('p', 'Hotkeys while this view is open: F fire at will · Z return fire · H hold fire · Q attack chosen participant · Space stop selected units · Esc close.', 'muted');
    shell.append(header, layout, commandBar, help);
    rtsOverlay.append(shell);
    document.body.append(rtsOverlay);
    renderRtsRouteList();
    updateRtsDisplay();
    storyteller.send('requestRtsSnapshot');
    const interval = Number(storyteller.getState()?.rts?.snapshotIntervalMs) || 1200;
    rtsSnapshotTimer = setInterval(() => {
      const state = storyteller.getState();
      if (!rtsOverlay || !state || state.session?.state !== 'active' || Number(state.session.story?.id) !== Number(rtsStoryId)) {
        closeRtsCommandView();
        return;
      }
      storyteller.send('requestRtsSnapshot');
    }, Math.max(700, interval));
  }

  function renderRtsRouteList() {
    if (!rtsRouteList) return;
    const markers = rtsStory?.spawnPoints?.filter(point => point.kind === 'patrol') || [];
    rtsRouteList.replaceChildren();
    if (!rtsPatrolRoute.length) rtsRouteList.append(element('p', 'Add at least two ordered waypoints for a looped patrol.', 'muted'));
    rtsPatrolRoute.forEach((id, index) => {
      const marker = markers.find(point => Number(point.id) === id);
      if (!marker) return;
      const row = element('div', undefined, 'flow-route-row'); row.append(element('span', (index + 1) + '. ' + marker.label));
      const up = element('button', '↑'); up.type = 'button'; up.disabled = index === 0;
      up.onclick = () => { [rtsPatrolRoute[index - 1], rtsPatrolRoute[index]] = [rtsPatrolRoute[index], rtsPatrolRoute[index - 1]]; renderRtsRouteList(); };
      const down = element('button', '↓'); down.type = 'button'; down.disabled = index === rtsPatrolRoute.length - 1;
      down.onclick = () => { [rtsPatrolRoute[index], rtsPatrolRoute[index + 1]] = [rtsPatrolRoute[index + 1], rtsPatrolRoute[index]]; renderRtsRouteList(); };
      const remove = element('button', '×'); remove.type = 'button'; remove.onclick = () => { rtsPatrolRoute.splice(index, 1); renderRtsRouteList(); };
      row.append(up, down, remove); rtsRouteList.append(row);
    });
  }

  function fitRtsBoard() {
    rtsView = null;
    drawRtsBoard(rtsSnapshot);
  }

  function changeRtsZoom(factor, anchorX, anchorY) {
    if (!rtsCanvas) return;
    if (!rtsView) drawRtsBoard(rtsSnapshot);
    if (!rtsView) return;
    const width = rtsCanvas.width, height = rtsCanvas.height;
    const px = anchorX == null ? width / 2 : anchorX;
    const py = anchorY == null ? height / 2 : anchorY;
    const worldX = rtsView.centerX + (px - width / 2) / rtsView.scale;
    const worldY = rtsView.centerY - (py - height / 2) / rtsView.scale;
    const nextScale = Math.max(0.001, Math.min(8, rtsView.scale * factor));
    rtsView.centerX = worldX - (px - width / 2) / nextScale;
    rtsView.centerY = worldY + (py - height / 2) / nextScale;
    rtsView.scale = nextScale;
    drawRtsBoard(rtsSnapshot);
  }

  function handleRtsBoardClick(event, orderMove) {
    if (!rtsCanvas || !rtsSnapshot) return;
    const rect = rtsCanvas.getBoundingClientRect();
    const px = (event.clientX - rect.left) * (rtsCanvas.width / rect.width);
    const py = (event.clientY - rect.top) * (rtsCanvas.height / rect.height);
    const points = rtsCanvas._rtsPoints || {};
    if (!orderMove) {
      const nearest = (points.units || []).map(item => ({ item, distance: Math.hypot(item.px - px, item.py - py) })).filter(item => item.distance <= 25).sort((a, b) => a.distance - b.distance)[0];
      if (nearest) {
        const id = String(nearest.item.unit.id);
        if (selectedRtsUnits.has(id)) selectedRtsUnits.delete(id); else selectedRtsUnits.add(id);
        updateRtsDisplay();
      }
      return;
    }
    if (!selectedRtsUnits.size) return;
    const projection = rtsCanvas._rtsProjection;
    if (!projection || !Number.isFinite(projection.scale) || projection.scale <= 0) return;
    const elevatedWorld = projection.world.filter(item => Number.isFinite(Number(item.z)));
    const nearestWorld = elevatedWorld.reduce((nearest, item) => {
      const distance = Math.hypot(Number(item.x) - (projection.centerX + (px - rtsCanvas.width / 2) / projection.scale), Number(item.y) - (projection.centerY - (py - rtsCanvas.height / 2) / projection.scale));
      return !nearest || distance < nearest.distance ? { item, distance } : nearest;
    }, null);
    const position = {
      x: projection.centerX + (px - rtsCanvas.width / 2) / projection.scale,
      y: projection.centerY - (py - rtsCanvas.height / 2) / projection.scale,
      z: Number(nearestWorld?.item?.z)
    };
    if (Number.isFinite(position.x) && Number.isFinite(position.y) && Number.isFinite(position.z)) {
      const fastSpeed = Number(storyteller.getState()?.encounters?.maxPatrolSpeed || rtsSpeedControl?.max || 3);
      sendRtsCommand('rts_move_point', { position, speed: event.shiftKey ? fastSpeed : Number(rtsSpeedControl?.value || 1) });
    }
  }

  function drawRtsBoard(snapshot) {
    if (!rtsCanvas) return;
    const ctx = rtsCanvas.getContext('2d');
    const width = rtsCanvas.width, height = rtsCanvas.height;
    ctx.clearRect(0, 0, width, height);
    ctx.fillStyle = '#0c1415'; ctx.fillRect(0, 0, width, height);
    const units = snapshot?.units || [], waypoints = snapshot?.waypoints || [], players = snapshot?.players || [];
    const world = [...units, ...waypoints, ...players].filter(item => Number.isFinite(Number(item.x)) && Number.isFinite(Number(item.y)));
    if (!world.length) {
      ctx.fillStyle = '#d8c5a4'; ctx.font = '22px sans-serif'; ctx.textAlign = 'center'; ctx.fillText('No tracked NPCs or patrol waypoints in this session yet.', width / 2, height / 2);
      rtsCanvas._rtsPoints = { units: [], waypoints: [] }; return;
    }
    if (!rtsView) {
      const minX = Math.min(...world.map(item => Number(item.x))), maxX = Math.max(...world.map(item => Number(item.x)));
      const minY = Math.min(...world.map(item => Number(item.y))), maxY = Math.max(...world.map(item => Number(item.y)));
      const spanX = Math.max(40, maxX - minX), spanY = Math.max(40, maxY - minY);
      rtsView = {
        centerX: (minX + maxX) / 2,
        centerY: (minY + maxY) / 2,
        scale: Math.max(0.001, Math.min(8, (width - 120) / spanX, (height - 120) / spanY))
      };
    }
    const { centerX, centerY, scale } = rtsView;
    const project = item => ({ px: width / 2 + (Number(item.x) - centerX) * scale, py: height / 2 - (Number(item.y) - centerY) * scale });
    rtsCanvas._rtsProjection = { centerX, centerY, scale, world };
    ctx.strokeStyle = '#ffffff12'; ctx.lineWidth = 1;
    for (let x = 50; x < width; x += 50) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke(); }
    for (let y = 50; y < height; y += 50) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke(); }
    const projectedUnits = units.map(unit => ({ unit, ...project(unit) }));
    const projectedWaypoints = waypoints.map(waypoint => ({ waypoint, ...project(waypoint) }));
    for (const item of projectedUnits) {
      const order = item.unit.order || {};
      const routeIds = order.kind === 'patrol' && Array.isArray(order.routeMarkerIds)
        ? order.routeMarkerIds.slice(Math.max(0, Number(order.routeIndex || 1) - 1))
        : [order.markerId];
      const route = order.targetCoords && order.kind === 'move'
        ? [project(order.targetCoords)]
        : routeIds.map(id => projectedWaypoints.find(point => Number(point.waypoint.id) === Number(id))).filter(Boolean);
      if (route.length && ['move', 'patrol'].includes(order.kind)) {
        ctx.strokeStyle = selectedRtsUnits.has(String(item.unit.id)) ? '#efc97b99' : '#d77c6299'; ctx.setLineDash([8, 7]);
        ctx.beginPath(); ctx.moveTo(item.px, item.py);
        for (const point of route) ctx.lineTo(point.px, point.py);
        if (order.kind === 'patrol' && route.length > 1) ctx.lineTo(route[0].px, route[0].py);
        ctx.stroke(); ctx.setLineDash([]);
      }
    }
    for (const item of projectedWaypoints) {
      ctx.fillStyle = '#e2bb72'; ctx.beginPath(); ctx.moveTo(item.px, item.py - 12); ctx.lineTo(item.px + 11, item.py); ctx.lineTo(item.px, item.py + 12); ctx.lineTo(item.px - 11, item.py); ctx.closePath(); ctx.fill();
      ctx.fillStyle = '#f1dfbf'; ctx.font = '15px sans-serif'; ctx.textAlign = 'left'; ctx.fillText(item.waypoint.label, item.px + 14, item.py + 5);
    }
    for (const player of players) {
      const point = project(player);
      ctx.fillStyle = '#74b8d9'; ctx.beginPath(); ctx.arc(point.px, point.py, 10, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = '#cae9f5'; ctx.font = '13px sans-serif'; ctx.textAlign = 'left'; ctx.fillText(player.name, point.px + 13, point.py + 4);
    }
    for (const item of projectedUnits) {
      const selected = selectedRtsUnits.has(String(item.unit.id));
      ctx.fillStyle = item.unit.alive ? selected ? '#f3c45f' : '#c96857' : '#666';
      ctx.strokeStyle = selected ? '#fff1bc' : '#301a19'; ctx.lineWidth = selected ? 4 : 2;
      ctx.beginPath(); ctx.arc(item.px, item.py, 15, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
      ctx.fillStyle = '#fff7e6'; ctx.font = 'bold 12px sans-serif'; ctx.textAlign = 'center'; ctx.fillText(String(item.unit.id).replace('npc-', ''), item.px, item.py + 4);
      ctx.font = '13px sans-serif'; ctx.textAlign = 'left'; ctx.fillText(item.unit.model, item.px + 19, item.py + 4);
    }
    rtsCanvas._rtsPoints = { units: projectedUnits, waypoints: projectedWaypoints };
  }

  function updateRtsDisplay() {
    if (!rtsOverlay) return;
    const state = storyteller.getState() || {};
    rtsSnapshot = Number(state.rtsSnapshot?.storyId) === Number(rtsStoryId) ? state.rtsSnapshot : null;
    const units = rtsSnapshot?.units || [];
    for (const id of [...selectedRtsUnits]) if (!units.some(unit => String(unit.id) === id && unit.alive)) selectedRtsUnits.delete(id);
    drawRtsBoard(rtsSnapshot);
    rtsSelectionSummary.textContent = selectedRtsUnits.size + ' unit(s) selected · ' + units.length + ' tracked in session.';
    rtsRoster.replaceChildren();
    if (!units.length) rtsRoster.append(element('p', 'Spawn NPCs in the live encounter panel to command them here.', 'muted'));
    for (const unit of units) {
      const card = element('button', undefined, 'rts-unit-card' + (selectedRtsUnits.has(String(unit.id)) ? ' selected' : ''));
      card.type = 'button';
      card.append(element('strong', unit.id + ' · ' + unit.model), element('span', unit.alive ? (unit.order?.status || 'holding') + ' · ' + (unit.stance || 'fire_at_will').replace(/_/g, ' ') + (Number.isFinite(Number(unit.health)) ? ' · ' + unit.health + ' HP' : '') : 'down'));
      card.onclick = () => { const id = String(unit.id); if (selectedRtsUnits.has(id)) selectedRtsUnits.delete(id); else selectedRtsUnits.add(id); updateRtsDisplay(); };
      rtsRoster.append(card);
    }
    const participantOptions = [{ value: '', label: 'Choose session participant' }, ...(rtsSnapshot?.players || []).map(player => ({ value: player.id, label: player.name + ' (#' + player.id + ')' }))];
    const selectedTarget = rtsTargetPicker?.value;
    if (rtsTargetPicker) {
      rtsTargetPicker.replaceChildren(...participantOptions.map(item => { const option = element('option', item.label); option.value = String(item.value); return option; }));
      if ([...rtsTargetPicker.options].some(option => option.value === selectedTarget)) rtsTargetPicker.value = selectedTarget;
    }
    rtsWeaponPanel.replaceChildren();
    const selected = units.filter(unit => selectedRtsUnits.has(String(unit.id)));
    if (!selected.length) rtsWeaponPanel.append(element('span', 'Select unit(s) to view configured weapons.', 'muted'));
    else {
      const common = (selected[0].weapons || []).filter(weapon => selected.every(unit => (unit.weapons || []).some(item => item.name === weapon.name)));
      if (!common.length) rtsWeaponPanel.append(element('span', 'No shared owner-configured weapons on this selection.', 'muted'));
      for (const weapon of common) {
        const enabled = selected.every(unit => (unit.weapons || []).find(item => item.name === weapon.name)?.enabled === true);
        const button = element('button', (enabled ? 'Disable ' : 'Enable ') + weapon.label); button.type = 'button';
        button.onclick = () => sendRtsCommand('rts_weapon', { weapon: weapon.name, enabled: !enabled });
        rtsWeaponPanel.append(button);
      }
    }
  }

  function handleRtsKeys(event) {
    if (!rtsOverlay) return;
    const key = event.key.toLowerCase();
    if (key === 'escape') { event.preventDefault(); event.stopImmediatePropagation(); closeRtsCommandView(); return; }
    if (['f', 'z', 'h', 'q', ' '].includes(key) && (event.target === document.body || event.target === rtsOverlay || !['INPUT', 'SELECT', 'TEXTAREA'].includes(event.target?.tagName))) {
      event.preventDefault(); event.stopImmediatePropagation();
      if (key === 'f') sendRtsCommand('rts_stance', { stance: 'fire_at_will' });
      else if (key === 'z') sendRtsCommand('rts_stance', { stance: 'return_fire' });
      else if (key === 'h') sendRtsCommand('rts_stance', { stance: 'hold_fire' });
      else if (key === ' ') sendRtsCommand('rts_stop');
      else if (key === 'q' && rtsTargetPicker?.value) sendRtsCommand('rts_target', { targetPlayerId: Number(rtsTargetPicker.value) });
    }
  }

  window.addEventListener('keydown', handleRtsKeys, true);
  window.addEventListener('ara:rtsSnapshot', updateRtsDisplay);
  window.addEventListener('message', event => {
    if (event.data?.action === 'close') closeRtsCommandView();
    if (event.data?.action === 'session' && event.data.payload?.state !== 'active') closeRtsCommandView();
  });

  function renderEncounterManager(panel, story) {
    const state = storyteller.getState() || {};
    const config = state.encounters || {};
    const points = story.spawnPoints || [];
    if (!points.some(point => String(point.id) === String(editingSpawnPointId))) editingSpawnPointId = null;
    const selected = points.find(point => String(point.id) === String(editingSpawnPointId));
    const section = element('div', undefined, 'card flow-encounter-manager');
    section.append(element('h3', 'NPC and prop encounters'));
    section.append(element('p', 'Capture named NPC, prop, and patrol positions on the server. Spawned entities are shared with nearby players and can be cleaned up at session end.', 'muted'));
    const create = element('button', 'New spawn marker');
    create.type = 'button'; create.onclick = () => { editingSpawnPointId = null; renderEditor(); };
    section.append(create);
    const form = element('div', undefined, 'flow-teleport-form');
    const label = inputControl(selected?.label || '', 'text'); label.maxLength = 100; label.placeholder = 'Marker name';
    const kind = selectControl([{ value: 'npc', label: 'NPC spawn' }, { value: 'prop', label: 'Prop spawn' }, { value: 'patrol', label: 'Patrol waypoint' }], selected?.kind || 'npc');
    form.append(field('Marker name', label), field('Marker use', kind));
    const capture = document.createElement('input'); capture.type = 'checkbox'; capture.checked = !selected;
    const captureLabel = element('label', selected ? ' Update position to my current location' : ' Capture my current in-game position and heading'); captureLabel.prepend(capture); form.append(captureLabel);
    const save = element('button', selected ? 'Save spawn marker' : 'Create spawn marker');
    save.type = 'button'; save.onclick = () => {
      if (!label.value.trim()) { label.focus(); return; }
      storyteller.send('spawnPointSave', { storyId: story.id, id: selected?.id, label: label.value, kind: kind.value, capturePosition: capture.checked });
    };
    form.append(save);
    if (selected) {
      const remove = element('button', 'Delete marker', 'danger'); remove.type = 'button';
      remove.onclick = () => { if (window.confirm('Delete spawn marker “' + selected.label + '”?')) storyteller.send('spawnPointDelete', { storyId: story.id, id: selected.id }); };
      form.append(remove);
    }
    section.append(form);
    if (points.length) {
      const list = element('div', undefined, 'item-grid');
      for (const point of points) {
        const card = element('div', undefined, 'card');
        card.append(element('strong', point.label), element('span', point.kind, 'tag'));
        card.append(element('p', 'Position: ' + [point.x, point.y, point.z].map(value => Number(value).toFixed(2)).join(', ') + ' · heading ' + Number(point.heading).toFixed(1) + '°', 'muted'));
        const edit = element('button', String(editingSpawnPointId) === String(point.id) ? 'Editing' : 'Edit marker');
        edit.type = 'button'; edit.onclick = () => { editingSpawnPointId = point.id; renderEditor(); };
        card.append(edit); list.append(card);
      }
      section.append(list);
    } else section.append(element('p', 'No spawn markers saved for this story.', 'muted'));

    const liveForStory = state.session?.state === 'active' && Number(state.session.story?.id) === Number(story.id);
    if (liveForStory) {
      section.append(element('h4', 'Live encounter controls'));
      const counts = state.session.encounters || {};
      section.append(element('p', 'Arachnid entities in this session: ' + Number(counts.npcs || 0) + ' NPC(s), ' + Number(counts.props || 0) + ' prop(s).', 'muted'));
      const openRts = element('button', 'Open NPC RTS Command View');
      openRts.type = 'button'; openRts.disabled = config.enabled !== true || state.rts?.enabled !== true;
      openRts.onclick = () => openRtsCommandView(story);
      section.append(openRts);
      if (config.enabled !== true) section.append(element('p', 'Encounter actions are disabled in server config. Enable Config.Encounters.enabled and grant the encounters ACE permission.', 'muted'));
      else if (state.rts?.enabled !== true) section.append(element('p', 'The separate RTS command view is disabled. Enable Config.Rts.enabled and grant the encounters ACE permission.', 'muted'));
      else section.append(element('p', 'Fire at Will NPCs automatically target the nearest connected session participant within the configured range. Set Config.Rts.autoEngage = false to require explicit attack orders.', 'muted'));
      const action = (name, labelText, data = {}) => {
        const button = element('button', labelText); button.type = 'button'; button.disabled = config.enabled !== true;
        button.onclick = () => storyteller.send('sessionEncounterAction', { action: name, ...data });
        section.append(button);
      };
      const pedModels = config.models?.ped || [], propModels = config.models?.prop || [];
      const npcMarkers = points.filter(point => point.kind === 'npc'), propMarkers = points.filter(point => point.kind === 'prop'), patrolMarkers = points.filter(point => point.kind === 'patrol');
      const npcModel = selectControl([{ value: '', label: 'Choose NPC model' }, ...pedModels.map(model => ({ value: model.name, label: model.label }))], pedModels[0]?.name);
      const npcMarker = selectControl([{ value: '', label: 'Choose NPC marker' }, ...npcMarkers.map(marker => ({ value: marker.id, label: marker.label }))], npcMarkers[0]?.id);
      const health = inputControl(150, 'number', 1, Number(config.maxNpcHealth || 1000), '1');
      const groupCount = inputControl(3, 'number', 1, Number(config.maxGroupCount || 12), '1');
      section.append(field('NPC model', npcModel), field('NPC spawn marker', npcMarker), field('NPC health', health));
      action('spawn_npc', 'Spawn NPC', { get model() { return npcModel.value; }, get spawnPointId() { return Number(npcMarker.value); }, get health() { return Number(health.value); } });
      section.append(field('Group count', groupCount));
      action('spawn_npc_group', 'Spawn NPC group', { get model() { return npcModel.value; }, get spawnPointId() { return Number(npcMarker.value); }, get health() { return Number(health.value); }, get count() { return Number(groupCount.value); } });
      action('remove_npc', 'Remove spawned NPCs');
      action('make_npc_hostile', 'Make NPCs hostile');
      const targetMode = selectControl([{ value: 'random', label: 'One random participant' }, { value: 'all', label: 'Distribute targets across participants' }], 'random');
      section.append(field('NPC target', targetMode)); action('set_npc_target', 'Set NPC targets', { get target() { return targetMode.value; } });
      const route = [];
      const routePicker = selectControl([{ value: '', label: 'Choose a patrol waypoint' }, ...patrolMarkers.map(marker => ({ value: marker.id, label: marker.label }))], '');
      const routeList = element('div', undefined, 'flow-route-list');
      const renderRoute = () => {
        routeList.replaceChildren();
        if (!route.length) routeList.append(element('p', 'Add at least two waypoints in the order NPCs should visit them.', 'muted'));
        route.forEach((markerId, index) => {
          const marker = patrolMarkers.find(item => Number(item.id) === markerId);
          if (!marker) return;
          const row = element('div', undefined, 'flow-route-row');
          row.append(element('span', (index + 1) + '. ' + marker.label));
          const up = element('button', '↑'); up.type = 'button'; up.disabled = index === 0;
          up.onclick = () => { [route[index - 1], route[index]] = [route[index], route[index - 1]]; renderRoute(); };
          const down = element('button', '↓'); down.type = 'button'; down.disabled = index === route.length - 1;
          down.onclick = () => { [route[index], route[index + 1]] = [route[index + 1], route[index]]; renderRoute(); };
          const remove = element('button', 'Remove'); remove.type = 'button';
          remove.onclick = () => { route.splice(index, 1); renderRoute(); };
          row.append(up, down, remove); routeList.append(row);
        });
      };
      const addWaypoint = element('button', 'Add waypoint'); addWaypoint.type = 'button';
      addWaypoint.onclick = () => {
        const markerId = Number(routePicker.value);
        if (markerId && patrolMarkers.some(marker => Number(marker.id) === markerId)) { route.push(markerId); renderRoute(); }
      };
      const waitSeconds = inputControl(3, 'number', 1, Number(config.maxPatrolWaitSeconds || 300), '1');
      section.append(field('Add waypoint to ordered route', routePicker), addWaypoint, routeList, field('Seconds at each waypoint', waitSeconds));
      renderRoute();
      action('patrol_route', 'Start NPC patrols', { get markerIds() { return route.slice(); }, get waitSeconds() { return Number(waitSeconds.value); } });
      const propModel = selectControl([{ value: '', label: 'Choose prop model' }, ...propModels.map(model => ({ value: model.name, label: model.label }))], propModels[0]?.name);
      const propMarker = selectControl([{ value: '', label: 'Choose prop marker' }, ...propMarkers.map(marker => ({ value: marker.id, label: marker.label }))], propMarkers[0]?.id);
      section.append(field('Prop model', propModel), field('Prop spawn marker', propMarker));
      action('spawn_prop', 'Spawn prop', { get model() { return propModel.value; }, get spawnPointId() { return Number(propMarker.value); } });
      action('delete_prop', 'Remove spawned props');
      if (!pedModels.length || !npcMarkers.length) section.append(element('p', 'NPC spawning needs an owner allowlisted ped model and an NPC spawn marker.', 'muted'));
      if (!propModels.length || !propMarkers.length) section.append(element('p', 'Prop spawning needs an owner allowlisted prop model and a prop marker.', 'muted'));
    }
    panel.append(section);
  }

  function renderWorldManager(panel, story) {
    const state = storyteller.getState() || {};
    const world = state.world || {};
    const targets = world.targets || [];
    const liveForStory = state.session?.state === 'active' && Number(state.session.story?.id) === Number(story.id);
    const section = element('div', undefined, 'card flow-world-manager');
    section.append(element('h3', 'Registered world controls'));
    section.append(element('p', 'Only named targets and operations configured by the server owner are available. Nearby nonparticipants may also see world changes.', 'muted'));
    if (!world.enabled) section.append(element('p', 'World controls are disabled. Enable Config.World.enabled and grant the world ACE permission.', 'muted'));
    if (!targets.length) section.append(element('p', 'The server owner must register targets in Config.World.targets.', 'muted'));
    if (liveForStory && targets.length) {
      const picker = selectControl([{ value: '', label: 'Choose registered target' }, ...targets.map(target => ({ value: target.id, label: target.label + ' · ' + target.kind }))], targets[0].id);
      section.append(field('Target', picker));
      const operationLabels = { open: 'Open door', close: 'Close door', lock: 'Lock door', unlock: 'Unlock door', enable: 'Enable entity', disable: 'Disable entity', trigger: 'Trigger configured event' };
      const controls = element('div', undefined, 'flow-toolbar');
      const renderOperations = () => {
        controls.replaceChildren();
        const target = targets.find(item => item.id === picker.value);
        for (const [operation, label] of Object.entries(operationLabels)) {
          if (!target?.actions?.[operation]) continue;
          const button = element('button', label); button.type = 'button'; button.disabled = !world.enabled;
          button.onclick = () => storyteller.send('sessionWorldAction', { targetId: target.id, action: operation });
          controls.append(button);
        }
      };
      picker.onchange = renderOperations;
      renderOperations(); section.append(controls);
    } else if (!liveForStory && state.session?.state === 'active') {
      section.append(element('p', 'Manual world actions are available only for the active story.', 'muted'));
    }
    section.append(element('p', 'Targets choose restore or persist behavior with restoreOnSessionEnd. Flow nodes use the same registered target list.', 'muted'));
    panel.append(section);
  }

  function renderEffectManager(panel, story) {
    const state = storyteller.getState() || {};
    const effects = state.effects || {};
    const liveForStory = state.session?.state === 'active' && Number(state.session.story?.id) === Number(story.id);
    const section = element('div', undefined, 'card flow-effect-manager');
    section.append(element('h3', 'Audio and visual effects'));
    section.append(element('p', 'Effects go only to connected players in the live session audience. Sound names come from the server allowlist.', 'muted'));
    if (!effects.enabled) section.append(element('p', 'Effects are disabled. Enable Config.Effects.enabled and grant the effects ACE permission.', 'muted'));
    if (liveForStory) {
      const sounds = effects.sounds || [];
      const sound = selectControl([{ value: '', label: 'Choose allowlisted sound' }, ...sounds.map(item => ({ value: item.id, label: item.label }))], sounds[0]?.id);
      const volume = inputControl(1, 'number', 0, Number(effects.maxVolume || 1), '0.05');
      const pitch = inputControl(100, 'number', Number(effects.minPitch || 50), Number(effects.maxPitch || 150), '1');
      const duration = inputControl(5, 'number', 1, Number(effects.maxDurationSeconds || 30), '0.1');
      section.append(field('Sound', sound), field('Volume', volume), field('Pitch', pitch));
      const send = (kind, data) => storyteller.send('sessionEffectAction', { kind, data });
      const button = (label, handler) => { const control = element('button', label); control.type = 'button'; control.disabled = !effects.enabled; control.onclick = handler; section.append(control); };
      button('Play sound for audience', () => sound.value && send('play_sound', { soundId: sound.value, volume: Number(volume.value), pitch: Number(pitch.value) }));
      button('Stop sound for audience', () => sound.value && send('stop_sound', { soundId: sound.value }));
      const fadeDirection = selectControl([{ value: 'out', label: 'Fade out' }, { value: 'in', label: 'Fade in' }], 'out');
      section.append(field('Screen fade direction', fadeDirection), field('Effect duration', duration));
      button('Send screen fade', () => send('screen_fade', { direction: fadeDirection.value, duration: Number(duration.value) }));
      const text = document.createElement('textarea'); text.maxLength = Number(effects.maxMessageLength || 1000); text.placeholder = 'Announcement or subtitle';
      section.append(field('Announcement / subtitle text', text));
      button('Send announcement', () => text.value.trim() && send('announcement', { text: text.value, duration: Number(duration.value) }));
      button('Send subtitle', () => text.value.trim() && send('subtitle', { text: text.value, duration: Number(duration.value) }));
      const amplitude = inputControl(1, 'number', 0, Number(effects.maxShakeAmplitude || 10), '0.1');
      const frequency = inputControl(1, 'number', 0, Number(effects.maxShakeFrequency || 10), '0.1');
      section.append(field('Shake amplitude', amplitude), field('Shake frequency', frequency));
      button('Send screen shake', () => send('screen_shake', { amplitude: Number(amplitude.value), frequency: Number(frequency.value), duration: Number(duration.value) }));
      if (!sounds.length) section.append(element('p', 'The server owner must add named entries to Config.Effects.sounds before sound actions can run.', 'muted'));
    } else if (state.session?.state === 'active') {
      section.append(element('p', 'Manual effects are available only for the active story.', 'muted'));
    }
    panel.append(section);
  }

  function renderEditor() {
    const content = document.getElementById('content');
    if (!content) return;
    document.getElementById('flow-editor')?.remove();
    const story = currentStory();
    if (!story?.id) return;
    const draft = getDraft(story);
    const panel = element('div', undefined, 'card flow-editor-panel');
    panel.id = 'flow-editor';
    panel.append(element('h3', 'Story flow graph'));
    panel.append(element('p', 'Drag nodes to arrange them. Choose an output, then an input, to connect the flow. Save the graph before starting the session.', 'muted'));

    const toolbar = element('div', undefined, 'flow-toolbar');
    const addSelect = document.createElement('select');
    addSelect.append(element('option', 'Add a flow node'));
    addSelect.options[0].value = '';
    for (const item of nodeTypes) {
      const option = element('option', item.label);
      option.value = item.type;
      addSelect.append(option);
    }
    addSelect.onchange = () => {
      const type = addSelect.value;
      addSelect.value = '';
      if (type) addNode(type);
    };
    const save = element('button', 'Save flow graph');
    save.type = 'button';
    save.onclick = () => {
      storyteller.send('flowSave', { storyId: story.id, graph: clone(draft) });
      saveMessage = 'Saving flow graph…';
      const status = document.getElementById('flow-save-state');
      if (status) status.textContent = saveMessage;
    };
    const reload = element('button', 'Reload saved graph');
    reload.type = 'button';
    reload.onclick = () => {
      if (!window.confirm('Discard unsaved flow edits and reload the saved graph?')) return;
      drafts.set(String(story.id), story.flow ? clone(story.flow) : { nodes: [], links: [] });
      selectedNodeId = null;
      pendingConnection = null;
      saveMessage = 'Loaded saved graph';
      renderEditor();
    };
    toolbar.append(addSelect, save, reload);
    panel.append(toolbar);

    const status = element('span', saveMessage || (story.flow?.nodes?.length ? 'Saved graph loaded' : 'No saved graph'), 'muted');
    status.id = 'flow-save-state';
    panel.append(status);
    const hint = element('p', pendingConnection ? 'Output selected. Click an input port to connect it.' : 'Click a node to edit its settings. Every branch output must be connected before the flow can start.', 'muted');
    panel.append(hint);

    const scroller = element('div', undefined, 'flow-canvas-scroll');
    const canvas = element('div', undefined, 'flow-canvas');
    scroller.append(canvas);
    panel.append(scroller);
    renderCanvas(canvas, draft, story);

    const selected = draft.nodes.find(item => item.id === selectedNodeId);
    if (selected) {
      const settings = element('div', undefined, 'card flow-node-settings');
      settings.append(element('h4', 'Edit ' + (labels[selected.type] || selected.type)));
      renderSettings(settings, selected, story);
      const removeNode = element('button', 'Delete node', 'danger');
      removeNode.type = 'button';
      removeNode.onclick = () => {
        draft.nodes = draft.nodes.filter(item => item.id !== selected.id);
        draft.links = draft.links.filter(link => link.fromNode !== selected.id && link.toNode !== selected.id);
        selectedNodeId = null;
        pendingConnection = null;
        markChanged('Unsaved flow changes');
        renderEditor();
      };
      settings.append(removeNode);
      panel.append(settings);
    }

    renderCutsceneManager(panel, story);
    renderEncounterManager(panel, story);
    renderWorldManager(panel, story);
    renderEffectManager(panel, story);
    renderTeleportManager(panel, story);

    if (draft.links.length) {
      const connections = element('div', undefined, 'card flow-connection-list');
      connections.append(element('h4', 'Connections'));
      for (const link of draft.links) {
        const from = draft.nodes.find(item => item.id === link.fromNode);
        const to = draft.nodes.find(item => item.id === link.toNode);
        const row = element('div', undefined, 'flow-connection-row');
        row.append(element('span', (labels[from?.type] || from?.type || 'Missing') + ' · ' + link.fromSocket + ' → ' + (labels[to?.type] || to?.type || 'Missing') + (link.toSocket && link.toSocket !== 'in' ? ' · input ' + link.toSocket : '')));
        const remove = element('button', 'Disconnect', 'danger');
        remove.type = 'button';
        remove.onclick = () => {
          draft.links = draft.links.filter(item => item.id !== link.id);
          markChanged('Unsaved flow changes');
          renderEditor();
        };
        row.append(remove);
        connections.append(row);
      }
      panel.append(connections);
    }
    content.append(panel);
  }

  function injectStyles() {
    if (document.getElementById('flow-editor-styles')) return;
    const style = element('style');
    style.id = 'flow-editor-styles';
    style.textContent = `
      .flow-editor-panel{margin-top:20px}.flow-toolbar{display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin:12px 0}.flow-canvas-scroll{overflow:auto;max-height:520px;border:1px solid #665337;background-color:#0d1414;background-image:radial-gradient(#8a7047 1px,transparent 1px);background-size:22px 22px;border-radius:4px;margin-top:10px}.flow-canvas{position:relative;min-width:920px;min-height:520px}.flow-links{position:absolute;inset:0;overflow:visible;pointer-events:none;z-index:1}.flow-node{position:absolute;width:225px;min-height:128px;border:1px solid #a7814b;border-radius:5px;background:linear-gradient(145deg,#30332c,#18201f);box-shadow:0 8px 18px #0009;z-index:2;color:#eee0c6;user-select:none}.flow-node.selected{outline:2px solid #e2bb72}.flow-node-head{padding:10px 12px;border-bottom:1px solid #775d39;color:#f0c77d;font-weight:bold;letter-spacing:.4px;cursor:grab}.flow-node-head:active{cursor:grabbing}.flow-input-row,.flow-output-row{display:flex;align-items:center;justify-content:space-between;padding:6px 9px;gap:6px}.flow-output-row{justify-content:flex-end;border-top:1px solid #ffffff12}.flow-port{padding:3px 7px;min-width:33px;border-radius:14px;font-size:10px;line-height:1.2;text-transform:uppercase}.flow-output-port{background:#463822}.flow-node-summary{padding:5px 11px;min-height:27px;color:#c4b393;font-size:12px;overflow-wrap:anywhere}.flow-field{display:block;margin:10px 0}.flow-field input,.flow-field select,.flow-field textarea{display:block;width:min(620px,100%);margin:5px 0 0}.flow-node-settings{margin-top:14px}.flow-connection-list,.flow-teleport-manager{margin-top:12px}.flow-connection-row{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:7px 0;border-top:1px solid #ffffff17}.flow-connection-row:first-of-type{border-top:0}.flow-connection-row button{padding:5px 9px;font-size:12px}.flow-route-list{margin:8px 0}.flow-route-row{display:flex;align-items:center;gap:8px;padding:6px 0;border-top:1px solid #ffffff17}.flow-route-row span{flex:1}.flow-route-row button{padding:5px 9px;font-size:12px}.flow-teleport-form{display:flex;flex-wrap:wrap;align-items:end;gap:8px}.flow-teleport-form .flow-field{flex:1 1 250px}.flow-teleport-form input[type=checkbox]{width:auto;display:inline-block}.flow-teleport-form button{margin:8px 6px 8px 0}@media(max-width:800px){.flow-canvas-scroll{max-height:420px}.flow-toolbar button,.flow-toolbar select{width:100%}}
    `;
    document.head.append(style);
  }

  function enhance() {
    const story = currentStory();
    if (!story?.id) {
      document.getElementById('flow-editor')?.remove();
      activeStoryId = null;
      selectedNodeId = null;
      return;
    }
    if (!document.getElementById('content')) return;
    if (document.getElementById('flow-editor')) return;
    renderEditor();
  }

  injectStyles();
  const observer = new MutationObserver(() => enhance());
  observer.observe(document.getElementById('content'), { childList: true, subtree: true });

  const originalRender = storyteller.render;
  storyteller.render = function (...args) {
    originalRender(...args);
    enhance();
  };
  window.render = storyteller.render;

  window.addEventListener('message', event => {
    const data = event.data || {};
    if (data.action === 'feedback' && typeof data.message === 'string' && /flow/i.test(data.message)) {
      saveMessage = data.message;
      const status = document.getElementById('flow-save-state');
      if (status) status.textContent = saveMessage;
    }
    if (data.action === 'select' && data.payload?.teleportMarkerId != null) {
      editingTeleportId = Number(data.payload.teleportMarkerId);
      if (document.getElementById('flow-editor')) renderEditor();
    }
  });
})();
