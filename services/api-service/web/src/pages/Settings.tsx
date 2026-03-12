import { Bell, Globe, Moon, Shield } from 'lucide-react'
import { useState } from 'react'

function Toggle({ checked, onChange }: { checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <button
      type="button"
      onClick={() => onChange(!checked)}
      className={`relative w-10 h-5.5 rounded-full transition-colors ${checked ? 'bg-brand-600' : 'bg-white/10'}`}
      style={{ height: '22px' }}
    >
      <span
        className={`absolute top-0.5 w-4 h-4 bg-white rounded-full shadow transition-transform ${checked ? 'translate-x-5' : 'translate-x-0.5'}`}
      />
    </button>
  )
}

function SettingRow({ icon: Icon, label, description, checked, onChange }: {
  icon: React.ElementType; label: string; description: string; checked: boolean; onChange: (v: boolean) => void
}) {
  return (
    <div className="flex items-center justify-between py-4 border-b border-white/5 last:border-0">
      <div className="flex items-center gap-3">
        <div className="w-9 h-9 rounded-xl bg-surface-700 flex items-center justify-center">
          <Icon size={15} className="text-gray-400" />
        </div>
        <div>
          <p className="text-white text-sm font-medium">{label}</p>
          <p className="text-gray-500 text-xs mt-0.5">{description}</p>
        </div>
      </div>
      <Toggle checked={checked} onChange={onChange} />
    </div>
  )
}

export default function Settings() {
  const [settings, setSettings] = useState({
    emailNotifications: true,
    orderAlerts: true,
    darkMode: true,
    twoFactor: false,
    apiAccess: true,
    marketingEmails: false,
  })

  const set = (key: keyof typeof settings) => (val: boolean) =>
    setSettings((s) => ({ ...s, [key]: val }))

  return (
    <div className="flex-1 bg-surface-900 overflow-auto">
      <div className="max-w-3xl mx-auto px-6 py-8">
        <h1 className="text-2xl font-bold text-white mb-6">Settings</h1>

        <div className="space-y-6">
          <div className="bg-surface-800 border border-white/5 rounded-2xl p-6">
            <h3 className="text-white font-semibold mb-1">Notifications</h3>
            <p className="text-gray-500 text-sm mb-4">Manage how you receive alerts and updates.</p>
            <SettingRow icon={Bell} label="Email Notifications" description="Receive updates via email" checked={settings.emailNotifications} onChange={set('emailNotifications')} />
            <SettingRow icon={Bell} label="Order Alerts" description="Get notified on order status changes" checked={settings.orderAlerts} onChange={set('orderAlerts')} />
            <SettingRow icon={Bell} label="Marketing Emails" description="News, tips and promotions" checked={settings.marketingEmails} onChange={set('marketingEmails')} />
          </div>

          <div className="bg-surface-800 border border-white/5 rounded-2xl p-6">
            <h3 className="text-white font-semibold mb-1">Appearance</h3>
            <p className="text-gray-500 text-sm mb-4">Customize your interface experience.</p>
            <SettingRow icon={Moon} label="Dark Mode" description="Use dark theme across the app" checked={settings.darkMode} onChange={set('darkMode')} />
          </div>

          <div className="bg-surface-800 border border-white/5 rounded-2xl p-6">
            <h3 className="text-white font-semibold mb-1">Security & Access</h3>
            <p className="text-gray-500 text-sm mb-4">Control your account security settings.</p>
            <SettingRow icon={Shield} label="Two-Factor Authentication" description="Add an extra layer of security" checked={settings.twoFactor} onChange={set('twoFactor')} />
            <SettingRow icon={Globe} label="API Access" description="Allow API key access to your account" checked={settings.apiAccess} onChange={set('apiAccess')} />
          </div>

          <div className="flex justify-end">
            <button className="px-5 py-2.5 rounded-xl bg-btn-gradient text-white text-sm font-medium shadow-glow hover:opacity-90 transition-all">
              Save Settings
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
