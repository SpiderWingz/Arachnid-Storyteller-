(() => {
  const storyteller = window.ArachnidStoryteller;
  if (!storyteller) return;

  let latestState = null;
  let editingAreaId = null;

  const node = (tag, text, cls) => {
    const element = document.createElement(tag);
    if (text !== undefined) element.textContent = String(text);
    if (cls) element.className = cls;
    return element;
  };

  function numberField(labelText, value, min, max, step = '1') {
    const label = node('label', labelText);
    const input = node('input');
    input.type = 'number';
    input.min = String(min);
    input.max = String(max);
    input.step = step;
    input.value = String(value);
    label.append(input);
    return { label, input };
  }

  function renderAreaManager() {
    const content = document.getElementById('content');
    if (!content || !latestState || !document.getElementById('app').style.display) return;
    if (content.querySelector('#area-manager')) return;

    const areas = latestState.areas || [];
    const selected = areas.find(area => String(area.id) === String(editingAreaId));
    const limits = latestState.areaLimits || { minRadius: 1, maxRadius: 500, minDimension: 1, maxDimension: 1000 };

    const panel = node('div', undefined, 'card');
    panel.id = 'area-manager';
    panel.append(node('h3', 'Saved session areas'));
    panel.append(node('p', 'Create a sphere or axis-aligned box centered on your current in-game position. The center is captured when you save.','muted'));

    const newArea = node('button', 'Create new area');
    newArea.onclick = () => {
      editingAreaId = null;
      panel.remove();
      renderAreaManager();
    };
    panel.append(newArea);

    const editor = node('div', undefined, 'card');
    editor.append(node('h4', selected ? 'Edit area #' + selected.id : 'New saved area'));
    const label = node('input');
    label.placeholder = 'Area name (up to 100 characters)';
    label.maxLength = 100;
    label.value = selected?.label || '';
    const shape = node('select');
    for (const [value, title] of [['sphere', 'Sphere'], ['box', 'Axis-aligned box']]) {
      const option = node('option', title);
      option.value = value;
      shape.append(option);
    }
    shape.value = selected?.shape === 'box' ? 'box' : 'sphere';

    const radius = numberField('Radius (meters)', selected?.radius ?? 25, limits.minRadius, limits.maxRadius, '0.5');
    const width = numberField('Width (meters)', selected?.width ?? 50, limits.minDimension, limits.maxDimension, '0.5');
    const depth = numberField('Depth (meters)', selected?.depth ?? 50, limits.minDimension, limits.maxDimension, '0.5');
    const height = numberField('Height (meters)', selected?.height ?? 20, limits.minDimension, limits.maxDimension, '0.5');
    const updateShapeFields = () => {
      radius.label.style.display = shape.value === 'sphere' ? 'block' : 'none';
      width.label.style.display = shape.value === 'box' ? 'block' : 'none';
      depth.label.style.display = shape.value === 'box' ? 'block' : 'none';
      height.label.style.display = shape.value === 'box' ? 'block' : 'none';
    };
    shape.onchange = updateShapeFields;
    updateShapeFields();

    const save = node('button', selected ? 'Save area at my current position' : 'Create area at my current position');
    save.onclick = () => {
      if (!label.value.trim()) {
        label.focus();
        return;
      }
      const values = shape.value === 'sphere'
        ? [Number(radius.input.value)]
        : [Number(width.input.value), Number(depth.input.value), Number(height.input.value)];
      if (!values.every(Number.isFinite)) return;
      if (shape.value === 'sphere' && (values[0] < limits.minRadius || values[0] > limits.maxRadius)) return radius.input.focus();
      if (shape.value === 'box' && values.some(value => value < limits.minDimension || value > limits.maxDimension)) return;
      storyteller.send('areaSave', {
        area: {
          id: selected?.id,
          label: label.value,
          shape: shape.value,
          radius: Number(radius.input.value),
          width: Number(width.input.value),
          depth: Number(depth.input.value),
          height: Number(height.input.value)
        }
      });
    };
    editor.append(label, shape, radius.label, width.label, depth.label, height.label, save);

    if (selected) {
      const remove = node('button', 'Delete saved area', 'danger');
      remove.onclick = () => {
        if (!window.confirm('Delete saved area “' + selected.label + '”?')) return;
        editingAreaId = null;
        storyteller.send('areaDelete', { id: selected.id });
      };
      editor.append(remove);
    }
    panel.append(editor);

    const list = node('div', undefined, 'item-grid');
    for (const area of areas) {
      const card = node('div', undefined, 'card');
      const dimensions = area.shape === 'sphere'
        ? 'Radius ' + Number(area.radius).toFixed(1) + 'm'
        : [area.width, area.depth, area.height].map(value => Number(value).toFixed(1)).join(' × ') + 'm';
      card.append(
        node('strong', area.label + ' · ' + (area.shape === 'sphere' ? 'Sphere' : 'Box')),
        node('p', dimensions, 'muted'),
        node('p', 'Center: ' + [area.x, area.y, area.z].map(value => Number(value).toFixed(2)).join(', '), 'muted')
      );
      const edit = node('button', String(editingAreaId) === String(area.id) ? 'Editing' : 'Edit area');
      edit.onclick = () => {
        editingAreaId = area.id;
        panel.remove();
        renderAreaManager();
      };
      card.append(edit);
      list.append(card);
    }
    if (!areas.length) panel.append(node('p', 'No saved areas yet.', 'muted'));
    else panel.append(list);
    content.append(panel);
  }

  function enhance() {
    renderAreaManager();
  }

  // Keep the area manager in sync as the story panel rebuilds its content.
  const observer = new MutationObserver(() => enhance());
  observer.observe(document.getElementById('content'), { childList: true, subtree: true });

  window.addEventListener('message', event => {
    const data = event.data || {};
    if (data.action === 'open' || data.action === 'data') {
      latestState = data.payload;
      if (data.action === 'open') editingAreaId = null;
      if (editingAreaId !== null && !(latestState.areas || []).some(area => String(area.id) === String(editingAreaId))) editingAreaId = null;
      document.getElementById('area-manager')?.remove();
    }
    if (data.action === 'select' && data.payload?.areaId != null) editingAreaId = Number(data.payload.areaId);
    if (data.action === 'close') {
      latestState = null;
      document.getElementById('area-manager')?.remove();
    }
    enhance();
  });

  // Preserve the existing story controls while appending the independent area editor.
  const originalRender = storyteller.render;
  storyteller.render = function (...args) {
    originalRender(...args);
    enhance();
  };
  window.render = storyteller.render;

})();
