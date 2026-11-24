(() => {
  const storyteller = window.ArachnidStoryteller;
  if (!storyteller) return;

  const drafts = new Map();
  let activeStoryId = null;
  let selectedNodeId = null;
  let editingTeleportId = null;
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
    { type: 'wait_objective', label: 'Wait for Objective', inputs: true, outputs: ['completed', 'failed'] },
    { type: 'wait_area', label: 'Wait for Area', inputs: true, outputs: ['next'] },
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
    const areas = storyteller.getState()?.areas || [];
    const actionConfig = storyteller.getState()?.playerActions || {};
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
      case 'wait_area': return { areaId: areas.length ? Number(areas[0].id) : null };
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

  function linkPorts(fromNode, fromSocket, toNode) {
    const story = currentStory();
    if (!story) return;
    const draft = getDraft(story);
    const source = draft.nodes.find(item => item.id === fromNode);
    const target = draft.nodes.find(item => item.id === toNode);
    if (!source || !target || source.type === 'end' || target.type === 'start' || source.id === target.id) return;
    const sourceType = nodeTypes.find(item => item.type === source.type);
    if (!sourceType?.outputs.includes(fromSocket)) return;
    if (draft.links.some(link => link.fromNode === fromNode && link.fromSocket === fromSocket)) {
      saveMessage = 'That output already has a connection. Remove it before reconnecting.';
      renderEditor();
      return;
    }
    if (draft.links.some(link => link.toNode === toNode)) {
      saveMessage = 'That node already has an input connection.';
      renderEditor();
      return;
    }
    draft.links.push({ id: uid('link'), fromNode, fromSocket, toNode, toSocket: 'in' });
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
    linkPorts(pendingConnection.fromNode, pendingConnection.fromSocket, nodeId);
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
      const toPort = canvas.querySelector('[data-role="input"][data-node-id="' + CSS.escape(link.toNode) + '"]');
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
      if (meta.inputs) {
        const row = element('div', undefined, 'flow-input-row');
        const input = element('button', 'in', 'flow-port');
        input.type = 'button';
        input.title = 'Connect a flow output here';
        input.dataset.role = 'input';
        input.dataset.nodeId = flowNode.id;
        input.dataset.socket = 'in';
        input.onclick = event => { event.stopPropagation(); portClick('input', flowNode.id, 'in'); };
        row.append(input, element('span', 'Input', 'muted'));
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
      case 'wait_area': return (storyteller.getState()?.areas || []).find(area => String(area.id) === String(data.areaId))?.label || 'Choose a saved area';
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
    } else if (flowNode.type === 'wait_area') {
      const areas = storyteller.getState()?.areas || [];
      const options = [{ value: '', label: 'Choose a saved area' }, ...areas.map(area => ({ value: area.id, label: area.label + ' · ' + area.shape }))];
      const control = selectControl(options, data.areaId);
      control.onchange = () => setData(flowNode, 'areaId', control.value ? Number(control.value) : null);
      editor.append(field('Saved area', control));
      editor.append(element('p', 'Waits without a timeout until an online participant in this session enters the area.', 'muted'));
    } else if (flowNode.type === 'wait_objective') {
      editor.append(element('p', 'Waits without a timeout until the active objective is marked completed or failed.', 'muted'));
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

    renderTeleportManager(panel, story);

    if (draft.links.length) {
      const connections = element('div', undefined, 'card flow-connection-list');
      connections.append(element('h4', 'Connections'));
      for (const link of draft.links) {
        const from = draft.nodes.find(item => item.id === link.fromNode);
        const to = draft.nodes.find(item => item.id === link.toNode);
        const row = element('div', undefined, 'flow-connection-row');
        row.append(element('span', (labels[from?.type] || from?.type || 'Missing') + ' · ' + link.fromSocket + ' → ' + (labels[to?.type] || to?.type || 'Missing')));
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
      .flow-editor-panel{margin-top:20px}.flow-toolbar{display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin:12px 0}.flow-canvas-scroll{overflow:auto;max-height:520px;border:1px solid #665337;background-color:#0d1414;background-image:radial-gradient(#8a7047 1px,transparent 1px);background-size:22px 22px;border-radius:4px;margin-top:10px}.flow-canvas{position:relative;min-width:920px;min-height:520px}.flow-links{position:absolute;inset:0;overflow:visible;pointer-events:none;z-index:1}.flow-node{position:absolute;width:225px;min-height:128px;border:1px solid #a7814b;border-radius:5px;background:linear-gradient(145deg,#30332c,#18201f);box-shadow:0 8px 18px #0009;z-index:2;color:#eee0c6;user-select:none}.flow-node.selected{outline:2px solid #e2bb72}.flow-node-head{padding:10px 12px;border-bottom:1px solid #775d39;color:#f0c77d;font-weight:bold;letter-spacing:.4px;cursor:grab}.flow-node-head:active{cursor:grabbing}.flow-input-row,.flow-output-row{display:flex;align-items:center;justify-content:space-between;padding:6px 9px;gap:6px}.flow-output-row{justify-content:flex-end;border-top:1px solid #ffffff12}.flow-port{padding:3px 7px;min-width:33px;border-radius:14px;font-size:10px;line-height:1.2;text-transform:uppercase}.flow-output-port{background:#463822}.flow-node-summary{padding:5px 11px;min-height:27px;color:#c4b393;font-size:12px;overflow-wrap:anywhere}.flow-field{display:block;margin:10px 0}.flow-field input,.flow-field select,.flow-field textarea{display:block;width:min(620px,100%);margin:5px 0 0}.flow-node-settings{margin-top:14px}.flow-connection-list,.flow-teleport-manager{margin-top:12px}.flow-connection-row{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:7px 0;border-top:1px solid #ffffff17}.flow-connection-row:first-of-type{border-top:0}.flow-connection-row button{padding:5px 9px;font-size:12px}.flow-teleport-form{display:flex;flex-wrap:wrap;align-items:end;gap:8px}.flow-teleport-form .flow-field{flex:1 1 250px}.flow-teleport-form input[type=checkbox]{width:auto;display:inline-block}.flow-teleport-form button{margin:8px 6px 8px 0}@media(max-width:800px){.flow-canvas-scroll{max-height:420px}.flow-toolbar button,.flow-toolbar select{width:100%}}
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
