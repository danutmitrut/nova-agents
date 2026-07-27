function parseSlackAllowedUserIds(value) {
  const ids = String(value || '')
    .split(',')
    .map((id) => id.trim())
    .filter(Boolean);

  if (ids.length === 0) {
    throw new Error('SLACK_ALLOWED_USER is required. Add one or more comma-separated Slack member IDs.');
  }

  const invalidIds = ids.filter((id) => !/^[UW][A-Z0-9]+$/.test(id));
  if (invalidIds.length > 0) {
    throw new Error('SLACK_ALLOWED_USER must contain only comma-separated Slack member IDs (U... or W...).');
  }

  return [...new Set(ids)];
}

module.exports = { parseSlackAllowedUserIds };
