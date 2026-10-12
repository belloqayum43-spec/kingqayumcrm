import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': Deno.env.get('APP_ORIGIN') ?? 'null',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Vary': 'Origin',
};
const respond = (status: number, body: unknown) => new Response(JSON.stringify(body), {
  status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
});

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return respond(405, { error: 'Method not allowed.' });

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) return respond(503, { error: 'Workspace administration is not configured.' });
  const authorization = req.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) return respond(401, { error: 'Sign in before managing workspace access.' });

  const authClient = createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { headers: { Authorization: authorization } },
  });
  const adminClient = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const { data: { user }, error: authError } = await authClient.auth.getUser();
  if (authError || !user) return respond(401, { error: 'Your session is invalid or expired. Sign in again.' });

  try {
    const input = await req.json();
    const workspaceId = typeof input.workspace_id === 'string' ? input.workspace_id : '';
    const action = input.action;
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(workspaceId)) {
      return respond(400, { error: 'A valid workspace_id is required.' });
    }
    const { data: membership, error: membershipError } = await adminClient
      .from('workspace_memberships').select('role').eq('workspace_id', workspaceId).eq('user_id', user.id).maybeSingle();
    if (membershipError) throw membershipError;
    if (!membership || !['owner', 'admin'].includes(membership.role)) {
      return respond(403, { error: 'Only a workspace owner or admin can manage invitations.' });
    }

    if (action === 'invite') {
      const email = typeof input.email === 'string' ? input.email.trim().toLowerCase() : '';
      const role = input.role === 'admin' ? 'admin' : 'member';
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return respond(400, { error: 'Enter a valid email address.' });
      if (role === 'admin' && membership.role !== 'owner') return respond(403, { error: 'Only the workspace owner can invite an admin.' });
      let page = 1;
      let existingUser: { id: string; email?: string; email_confirmed_at?: string } | undefined;
      while (!existingUser) {
        const { data, error } = await adminClient.auth.admin.listUsers({ page, perPage: 1000 });
        if (error) throw error;
        existingUser = data.users.find((candidate) => candidate.email?.toLowerCase() === email);
        if (existingUser || data.users.length < 1000) break;
        page += 1;
      }
      if (existingUser) {
        const { data: existingMembership, error } = await adminClient.from('workspace_memberships')
          .select('user_id').eq('workspace_id', workspaceId).eq('user_id', existingUser.id).maybeSingle();
        if (error) throw error;
        if (existingMembership) return respond(409, { error: 'This user is already a workspace member.' });
      }
      const appOrigin = Deno.env.get('APP_ORIGIN');
      if (!appOrigin || !appOrigin.startsWith('https://')) return respond(503, { error: 'A trusted HTTPS APP_ORIGIN must be configured.' });
      let invitedId = existingUser?.email_confirmed_at ? existingUser.id : undefined;
      if (!invitedId) {
        const { data, error } = await adminClient.auth.admin.inviteUserByEmail(email, {
          redirectTo: `${appOrigin.replace(/\/$/, '')}/`,
          data: { kingqayum_workspace_invite: workspaceId },
        });
        if (error) throw error;
        invitedId = data.user?.id;
      }
      if (!invitedId) throw new Error('The invitation did not return a user ID.');
      const { error: insertError } = await adminClient.from('workspace_memberships').insert({
        workspace_id: workspaceId, user_id: invitedId, role, invited_by: user.id,
      });
      // Do not delete the Auth user on failure: an invitation endpoint may
      // return an existing account, and deleting it would affect other apps.
      if (insertError) throw insertError;
      return respond(200, { invited: true, role, email });
    }

    if (action === 'revoke') {
      const targetId = typeof input.user_id === 'string' ? input.user_id : '';
      if (!targetId) return respond(400, { error: 'A user_id is required.' });
      const { data: target, error } = await adminClient.from('workspace_memberships')
        .select('role').eq('workspace_id', workspaceId).eq('user_id', targetId).maybeSingle();
      if (error) throw error;
      if (!target) return respond(404, { error: 'Workspace membership was not found.' });
      if (target.role === 'owner') return respond(403, { error: 'The owner role cannot be revoked here.' });
      if (target.role === 'admin' && membership.role !== 'owner') return respond(403, { error: 'Only the owner can revoke an admin.' });
      const { error: removeError } = await adminClient.from('workspace_memberships')
        .delete().eq('workspace_id', workspaceId).eq('user_id', targetId);
      if (removeError) throw removeError;
      return respond(200, { revoked: true });
    }
    return respond(400, { error: 'Action must be invite or revoke.' });
  } catch (error) {
    console.error('workspace-admin failed', error);
    return respond(500, { error: 'Workspace access could not be changed. Check server logs or try again.' });
  }
});
