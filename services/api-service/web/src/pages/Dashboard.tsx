import {
  AlertCircle,
  ArrowUpRight,
  Box,
  CheckCircle2,
  Clock,
  DollarSign,
  Plus,
  ShoppingCart,
  TrendingUp,
  XCircle,
} from 'lucide-react'
import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { Bar, BarChart, Cell, Pie, PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { useAuth } from '../context/AuthContext'
import { cancelOrder, createOrder, getOrders, getStats } from '../services/api'
import type { Order, Stats } from '../types'

const STATUS_CONFIG = {
  pending:    { color: 'text-yellow-400', bg: 'bg-yellow-400/10', border: 'border-yellow-400/30', icon: Clock },
  processing: { color: 'text-blue-400',   bg: 'bg-blue-400/10',   border: 'border-blue-400/30',   icon: AlertCircle },
  completed:  { color: 'text-green-400',  bg: 'bg-green-400/10',  border: 'border-green-400/30',  icon: CheckCircle2 },
  cancelled:  { color: 'text-red-400',    bg: 'bg-red-400/10',    border: 'border-red-400/30',    icon: XCircle },
} as const

function StatusBadge({ status }: { status: string }) {
  const cfg = STATUS_CONFIG[status as keyof typeof STATUS_CONFIG] ?? STATUS_CONFIG.pending
  const Icon = cfg.icon
  return (
    <span className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium border ${cfg.color} ${cfg.bg} ${cfg.border}`}>
      <Icon size={11} />
      {status.charAt(0).toUpperCase() + status.slice(1)}
    </span>
  )
}

function StatCard({ label, value, sub, icon: Icon, gradient }: {
  label: string; value: string; sub: string; icon: React.ElementType; gradient: string
}) {
  return (
    <div className="bg-surface-800 border border-white/5 rounded-2xl p-6 hover:border-white/10 transition-all group">
      <div className="flex items-start justify-between mb-4">
        <div className={`w-10 h-10 rounded-xl flex items-center justify-center ${gradient}`}>
          <Icon size={18} className="text-white" />
        </div>
        <TrendingUp size={14} className="text-gray-600 group-hover:text-brand-500 transition-colors" />
      </div>
      <p className="text-2xl font-bold text-white">{value}</p>
      <p className="text-gray-400 text-sm mt-1">{label}</p>
      <p className="text-gray-600 text-xs mt-2">{sub}</p>
    </div>
  )
}

const PIE_COLORS = ['#eab308', '#3b82f6', '#22c55e', '#ef4444']

export default function Dashboard() {
  const { user } = useAuth()
  const [stats, setStats] = useState<Stats | null>(null)
  const [recentOrders, setRecentOrders] = useState<Order[]>([])
  const [loading, setLoading] = useState(true)
  const [showNewOrder, setShowNewOrder] = useState(false)
  const [newProduct, setNewProduct] = useState('')
  const [newQty, setNewQty] = useState(1)
  const [newPrice, setNewPrice] = useState('')
  const [submitting, setSubmitting] = useState(false)

  async function loadData() {
    try {
      const [s, o] = await Promise.all([getStats(), getOrders(1, 5)])
      setStats(s)
      setRecentOrders(o.items)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { loadData() }, [])

  async function handleCreateOrder(e: React.FormEvent) {
    e.preventDefault()
    setSubmitting(true)
    try {
      await createOrder({ product_name: newProduct, quantity: newQty, unit_price: parseFloat(newPrice) })
      setShowNewOrder(false)
      setNewProduct(''); setNewQty(1); setNewPrice('')
      loadData()
    } finally {
      setSubmitting(false)
    }
  }

  async function handleCancel(id: string) {
    await cancelOrder(id)
    loadData()
  }

  const pieData = stats ? [
    { name: 'Pending',    value: stats.pending },
    { name: 'Processing', value: stats.processing },
    { name: 'Completed',  value: stats.completed },
    { name: 'Cancelled',  value: stats.cancelled },
  ].filter(d => d.value > 0) : []

  const barData = stats ? [
    { name: 'Pending',    orders: stats.pending,    fill: '#eab308' },
    { name: 'Processing', orders: stats.processing, fill: '#3b82f6' },
    { name: 'Completed',  orders: stats.completed,  fill: '#22c55e' },
    { name: 'Cancelled',  orders: stats.cancelled,  fill: '#ef4444' },
  ] : []

  const firstName = user?.full_name.split(' ')[0] ?? 'there'

  if (loading) {
    return (
      <div className="flex-1 flex items-center justify-center bg-surface-900">
        <div className="w-10 h-10 border-4 border-brand-600 border-t-transparent rounded-full animate-spin" />
      </div>
    )
  }

  return (
    <div className="flex-1 bg-surface-900 overflow-auto">
      <div className="max-w-7xl mx-auto px-6 py-8">
        {/* Header */}
        <div className="flex items-center justify-between mb-8">
          <div>
            <h1 className="text-2xl font-bold text-white">Good {getGreeting()}, {firstName} 👋</h1>
            <p className="text-gray-400 mt-1 text-sm">
              {new Date().toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })}
            </p>
          </div>
          <button
            onClick={() => setShowNewOrder(true)}
            className="flex items-center gap-2 px-4 py-2.5 rounded-xl bg-btn-gradient text-white text-sm font-medium shadow-glow hover:opacity-90 active:scale-[0.98] transition-all"
          >
            <Plus size={16} />
            New Order
          </button>
        </div>

        {/* Stats Grid */}
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
          <StatCard
            label="Total Orders"
            value={String(stats?.total_orders ?? 0)}
            sub={`${stats?.this_month_orders ?? 0} this month`}
            icon={ShoppingCart}
            gradient="bg-gradient-to-br from-brand-600 to-blue-600"
          />
          <StatCard
            label="Pending"
            value={String(stats?.pending ?? 0)}
            sub="Awaiting processing"
            icon={Clock}
            gradient="bg-gradient-to-br from-yellow-600 to-orange-600"
          />
          <StatCard
            label="Completed"
            value={String(stats?.completed ?? 0)}
            sub="Successfully fulfilled"
            icon={CheckCircle2}
            gradient="bg-gradient-to-br from-green-600 to-emerald-600"
          />
          <StatCard
            label="Revenue"
            value={`$${(stats?.total_revenue ?? 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`}
            sub={`$${(stats?.this_month_revenue ?? 0).toLocaleString('en-US', { minimumFractionDigits: 2 })} this month`}
            icon={DollarSign}
            gradient="bg-gradient-to-br from-purple-600 to-pink-600"
          />
        </div>

        {/* Charts + Recent Orders */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-8">
          {/* Bar Chart */}
          <div className="lg:col-span-2 bg-surface-800 border border-white/5 rounded-2xl p-6">
            <h2 className="text-white font-semibold mb-4">Order Distribution</h2>
            {barData.every(d => d.orders === 0) ? (
              <div className="h-48 flex items-center justify-center text-gray-600 text-sm">No orders yet</div>
            ) : (
              <ResponsiveContainer width="100%" height={200}>
                <BarChart data={barData} barSize={40}>
                  <XAxis dataKey="name" tick={{ fill: '#6b7280', fontSize: 12 }} axisLine={false} tickLine={false} />
                  <YAxis tick={{ fill: '#6b7280', fontSize: 12 }} axisLine={false} tickLine={false} allowDecimals={false} />
                  <Tooltip
                    contentStyle={{ backgroundColor: '#0d0d1f', border: '1px solid rgba(255,255,255,0.1)', borderRadius: 8, color: '#fff' }}
                    cursor={{ fill: 'rgba(255,255,255,0.03)' }}
                  />
                  <Bar dataKey="orders" radius={[6, 6, 0, 0]}>
                    {barData.map((entry, i) => <Cell key={i} fill={entry.fill} />)}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            )}
          </div>

          {/* Pie Chart */}
          <div className="bg-surface-800 border border-white/5 rounded-2xl p-6">
            <h2 className="text-white font-semibold mb-4">Status Breakdown</h2>
            {pieData.length === 0 ? (
              <div className="h-48 flex items-center justify-center text-gray-600 text-sm">No data</div>
            ) : (
              <>
                <ResponsiveContainer width="100%" height={160}>
                  <PieChart>
                    <Pie data={pieData} cx="50%" cy="50%" innerRadius={45} outerRadius={70} dataKey="value" paddingAngle={3}>
                      {pieData.map((_, i) => <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />)}
                    </Pie>
                    <Tooltip
                      contentStyle={{ backgroundColor: '#0d0d1f', border: '1px solid rgba(255,255,255,0.1)', borderRadius: 8, color: '#fff' }}
                    />
                  </PieChart>
                </ResponsiveContainer>
                <div className="space-y-1 mt-2">
                  {pieData.map((d, i) => (
                    <div key={d.name} className="flex items-center justify-between text-xs">
                      <div className="flex items-center gap-2">
                        <div className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: PIE_COLORS[i % PIE_COLORS.length] }} />
                        <span className="text-gray-400">{d.name}</span>
                      </div>
                      <span className="text-white font-medium">{d.value}</span>
                    </div>
                  ))}
                </div>
              </>
            )}
          </div>
        </div>

        {/* Recent Orders */}
        <div className="bg-surface-800 border border-white/5 rounded-2xl">
          <div className="flex items-center justify-between px-6 py-4 border-b border-white/5">
            <h2 className="text-white font-semibold">Recent Orders</h2>
            <Link to="/orders" className="flex items-center gap-1 text-brand-400 hover:text-brand-300 text-sm font-medium transition-colors">
              View all <ArrowUpRight size={14} />
            </Link>
          </div>

          {recentOrders.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-16 text-gray-600">
              <Box size={40} className="mb-3 opacity-50" />
              <p className="font-medium">No orders yet</p>
              <p className="text-sm mt-1">Create your first order to get started</p>
              <button
                onClick={() => setShowNewOrder(true)}
                className="mt-4 flex items-center gap-2 px-4 py-2 rounded-lg bg-brand-600/20 text-brand-400 text-sm hover:bg-brand-600/30 transition-all border border-brand-600/30"
              >
                <Plus size={14} /> Create order
              </button>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr className="border-b border-white/5">
                    {['Product', 'Qty', 'Unit Price', 'Total', 'Status', 'Date', ''].map((h) => (
                      <th key={h} className="text-left px-6 py-3 text-xs font-medium text-gray-500 uppercase tracking-wider">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-white/5">
                  {recentOrders.map((order) => (
                    <tr key={order.id} className="hover:bg-white/2 transition-colors group">
                      <td className="px-6 py-4 text-white text-sm font-medium">{order.product_name}</td>
                      <td className="px-6 py-4 text-gray-400 text-sm">{order.quantity}</td>
                      <td className="px-6 py-4 text-gray-400 text-sm">${order.unit_price.toFixed(2)}</td>
                      <td className="px-6 py-4 text-white text-sm font-medium">${order.total_amount.toFixed(2)}</td>
                      <td className="px-6 py-4"><StatusBadge status={order.status} /></td>
                      <td className="px-6 py-4 text-gray-500 text-xs">{new Date(order.created_at).toLocaleDateString()}</td>
                      <td className="px-6 py-4">
                        {order.status === 'pending' && (
                          <button
                            onClick={() => handleCancel(order.id)}
                            className="text-xs text-gray-600 hover:text-red-400 transition-colors opacity-0 group-hover:opacity-100"
                          >
                            Cancel
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>

      {/* New Order Modal */}
      {showNewOrder && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 p-4">
          <div className="bg-surface-800 border border-white/10 rounded-2xl p-6 w-full max-w-md shadow-card animate-slide-up">
            <h3 className="text-white font-semibold text-lg mb-5">New Order</h3>
            <form onSubmit={handleCreateOrder} className="space-y-4">
              <div>
                <label className="block text-sm text-gray-300 mb-1.5">Product name</label>
                <input
                  value={newProduct}
                  onChange={(e) => setNewProduct(e.target.value)}
                  required
                  placeholder="Enterprise SSD 1TB"
                  className="w-full bg-surface-700/60 border border-white/10 rounded-lg px-3 py-2.5 text-white text-sm placeholder-gray-600 focus:outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500/50"
                />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-sm text-gray-300 mb-1.5">Quantity</label>
                  <input
                    type="number"
                    min={1}
                    value={newQty}
                    onChange={(e) => setNewQty(Number(e.target.value))}
                    required
                    className="w-full bg-surface-700/60 border border-white/10 rounded-lg px-3 py-2.5 text-white text-sm focus:outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500/50"
                  />
                </div>
                <div>
                  <label className="block text-sm text-gray-300 mb-1.5">Unit price ($)</label>
                  <input
                    type="number"
                    min={0}
                    step={0.01}
                    value={newPrice}
                    onChange={(e) => setNewPrice(e.target.value)}
                    required
                    placeholder="0.00"
                    className="w-full bg-surface-700/60 border border-white/10 rounded-lg px-3 py-2.5 text-white text-sm placeholder-gray-600 focus:outline-none focus:border-brand-500 focus:ring-1 focus:ring-brand-500/50"
                  />
                </div>
              </div>
              {newPrice && newQty > 0 && (
                <p className="text-brand-400 text-sm font-medium">
                  Total: ${(parseFloat(newPrice || '0') * newQty).toFixed(2)}
                </p>
              )}
              <div className="flex gap-3 pt-2">
                <button
                  type="button"
                  onClick={() => setShowNewOrder(false)}
                  className="flex-1 py-2.5 rounded-lg border border-white/10 text-gray-400 text-sm hover:bg-white/5 transition-all"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={submitting}
                  className="flex-1 py-2.5 rounded-lg bg-btn-gradient text-white text-sm font-medium shadow-glow hover:opacity-90 disabled:opacity-50 transition-all"
                >
                  {submitting ? 'Creating...' : 'Create Order'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  )
}

function getGreeting() {
  const h = new Date().getHours()
  return h < 12 ? 'morning' : h < 17 ? 'afternoon' : 'evening'
}
