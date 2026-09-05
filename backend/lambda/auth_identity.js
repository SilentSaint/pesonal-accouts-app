const crypto = require('crypto');

function deriveUserScopeId(email) {
  return crypto
    .createHash('sha256')
    .update(email.toLowerCase().trim())
    .digest('hex')
    .substring(0, 32);
}

function resolveGatewayAuthenticatedUserPk(event) {
  const claims = event.requestContext?.authorizer?.jwt?.claims;
  const email = claims?.email;
  const emailVerified = claims?.email_verified;
  return (emailVerified === true || emailVerified === 'true')
    && typeof email === 'string' && email.trim()
    ? `USER#${deriveUserScopeId(email)}`
    : null;
}

module.exports = {
  deriveUserScopeId,
  resolveGatewayAuthenticatedUserPk,
};
