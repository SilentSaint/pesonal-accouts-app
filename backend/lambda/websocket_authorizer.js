const https = require('https');
const { deriveUserScopeId } = require('./auth_identity');

function fetchGoogleTokenInfo(idToken) {
  return new Promise((resolve, reject) => {
    const request = https.get(
      `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`,
      { timeout: 3000 },
      (response) => {
        let body = '';
        response.setEncoding('utf8');
        response.on('data', (chunk) => { body += chunk; });
        response.on('end', () => {
          if (response.statusCode !== 200) {
            reject(new Error(`Google token validation returned ${response.statusCode}`));
            return;
          }
          try {
            resolve(JSON.parse(body));
          } catch (_) {
            reject(new Error('Google token validation returned invalid JSON'));
          }
        });
      },
    );
    request.on('timeout', () => request.destroy(new Error('Google token validation timed out')));
    request.on('error', reject);
  });
}

function authorizationResult(effect, methodArn, principalId, context = {}) {
  return {
    principalId,
    policyDocument: {
      Version: '2012-10-17',
      Statement: [{
        Action: 'execute-api:Invoke',
        Effect: effect,
        Resource: methodArn,
      }],
    },
    context,
  };
}

function createWebSocketAuthorizer({
  clientId = process.env.GOOGLE_CLIENT_ID,
  fetchTokenInfo = fetchGoogleTokenInfo,
} = {}) {
  return async (event) => {
    const methodArn = event?.methodArn || '*';
    const token = event?.queryStringParameters?.token;
    if (!clientId || typeof token !== 'string' || token.length === 0) {
      return authorizationResult('Deny', methodArn, 'unauthenticated');
    }

    try {
      const identity = await fetchTokenInfo(token);
      const email = identity?.email;
      const emailVerified = identity?.email_verified;
      if (
        identity?.aud !== clientId ||
        (emailVerified !== true && emailVerified !== 'true') ||
        typeof email !== 'string' ||
        !email.trim()
      ) {
        return authorizationResult('Deny', methodArn, 'unauthenticated');
      }

      const userPk = `USER#${deriveUserScopeId(email)}`;
      return authorizationResult('Allow', methodArn, userPk, { userPk });
    } catch (_) {
      return authorizationResult('Deny', methodArn, 'unauthenticated');
    }
  };
}

module.exports = {
  createWebSocketAuthorizer,
  handler: createWebSocketAuthorizer(),
};
