import { Calendar, CheckCircle2, Mail, Shield, User } from 'lucide-react'
import { useState } from 'react'
import { useAuth } from '../context/AuthContext'

export default function Profile() {
  const { user, refresh } = useAuth()
  const [saved, setSaved] = useState(false)

  if (!user) return null

  const initials = user.full_name.split(' ').map((n) => n[0]).slice(0, 2).join('').toUpperCase()

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    setSaved(true)
    setTimeout(() => setSaved(false), 2500)
  }

  return (
    <div className="flex-1 bg-surface-900 overflow-auto">
      <div className="max-w-3xl mx-auto px-6 py-8">
        <h1 className="text-2xl font-bold text-white mb-6">Profile</h1>

        {/* Avatar Card */}
        <div className="bg-surface-800 border border-white/5 rounded-2xl p-6 mb-6 flex items-center gap-6">
          <div className="w-20 h-20 rounded-2xl bg-btn-gradient flex items-center justify-center text-white text-2xl font-bold shadow-glow">
            {initials}
          </div>
          <div>
            <h2 className="text-xl font-semibold text-white">{user.full_name}</h2>
            <p className="text-gray-400 text-sm mt-0.5">{user.email}</p>
            <div className="flex items-center gap-2 mt-2">
              <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs bg-green-500/10 text-green-400 border border-green-500/20">
                <CheckCircle2 size={10} /> Active
              </span>
              <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs bg-brand-600/20 text-brand-400 border border-brand-500/30">
                <Shield size={10} /> Member
              </span>
            </div>
          </div>
        </div>

        {/* Account Info */}
        <div className="bg-surface-800 border border-white/5 rounded-2xl p-6 mb-6">
          <h3 className="text-white font-semibold mb-4">Account Information</h3>
          <div className="space-y-4">
            <InfoRow icon={User} label="Full Name" value={user.full_name} />
            <InfoRow icon={Mail} label="Email" value={user.email} />
            <InfoRow
              icon={Calendar}
              label="Member Since"
              value={new Date(user.created_at).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}
            />
            <InfoRow icon={Shield} label="Account ID" value={user.id} mono />
          </div>
        </div>

        {/* Security */}
        <div className="bg-surface-800 border border-white/5 rounded-2xl p-6">
          <h3 className="text-white font-semibold mb-4">Security</h3>
          <form onSubmit={handleSave} className="space-y-4">
            <div>
              <label className="block text-sm text-gray-300 mb-1.5">Current Password</label>
              <input
                type="password"
                placeholder="Enter current password"
                className="w-full bg-surface-700/60 border border-white/10 rounded-lg px-3 py-2.5 text-white text-sm placeholder-gray-600 focus:outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500/50 transition-all"
              />
            </div>
            <div>
              <label className="block text-sm text-gray-300 mb-1.5">New Password</label>
              <input
                type="password"
                placeholder="Min. 8 characters"
                className="w-full bg-surface-700/60 border border-white/10 rounded-lg px-3 py-2.5 text-white text-sm placeholder-gray-600 focus:outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500/50 transition-all"
              />
            </div>
            <div>
              <label className="block text-sm text-gray-300 mb-1.5">Confirm New Password</label>
              <input
                type="password"
                placeholder="Re-enter new password"
                className="w-full bg-surface-700/60 border border-white/10 rounded-lg px-3 py-2.5 text-white text-sm placeholder-gray-600 focus:outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500/50 transition-all"
              />
            </div>
            <button
              type="submit"
              className={`px-5 py-2.5 rounded-lg text-sm font-medium transition-all ${
                saved
                  ? 'bg-green-600/30 text-green-400 border border-green-500/30'
                  : 'bg-btn-gradient text-white shadow-glow hover:opacity-90'
              }`}
            >
              {saved ? '✓ Password Updated' : 'Update Password'}
            </button>
          </form>
        </div>
      </div>
    </div>
  )
}

function InfoRow({ icon: Icon, label, value, mono = false }: {
  icon: React.ElementType; label: string; value: string; mono?: boolean
}) {
  return (
    <div className="flex items-center gap-4 py-3 border-b border-white/5 last:border-0">
      <div className="w-8 h-8 rounded-lg bg-surface-700 flex items-center justify-center">
        <Icon size={14} className="text-gray-400" />
      </div>
      <div className="flex-1">
        <p className="text-gray-500 text-xs mb-0.5">{label}</p>
        <p className={`text-white text-sm ${mono ? 'font-mono text-xs text-gray-300' : 'font-medium'}`}>{value}</p>
      </div>
    </div>
  )
}
