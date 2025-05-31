#!/bin/bash

set -e

echo "⏳ در حال شناسایی اینترفیس اصلی شبکه..."

iface=$(ip route | grep default | awk '{print $5}')

if [ -z "$iface" ]; then
  echo "❌ اینترفیس پیش‌فرض پیدا نشد. لطفاً دستی بررسی کنید."
  exit 1
fi

echo "✅ اینترفیس شناسایی شده: $iface"

echo "🔧 در حال تغییر موقتی MTU به 1476..."
ip link set dev "$iface" mtu 1476

echo "✅ تغییر موقتی MTU انجام شد."

# شناسایی توزیع
. /etc/os-release

echo "📦 توزیع سیستم: $ID"

# تغییر دائمی بر اساس نوع توزیع
case "$ID" in
  ubuntu|debian)
    # اگر Netplan استفاده می‌شود
    if command -v netplan &>/dev/null && ls /etc/netplan/*.yaml &>/dev/null; then
      netplan_file=$(ls /etc/netplan/*.yaml | head -n1)
      echo "📝 در حال اعمال تغییر در Netplan: $netplan_file"

      # حذف مقادیر قبلی mtu
      sed -i '/mtu:/d' "$netplan_file"

      # اضافه کردن مقدار جدید mtu در جای مناسب
      if grep -q "mtu:" "$netplan_file"; then
        echo "⚠ MTU قبلاً تنظیم شده. بررسی دستی پیشنهاد می‌شود."
      else
        sed -i "/$iface:/,/^[^ ]/ s/\(dhcp4:.*\)/\1\n      mtu: 1476/" "$netplan_file"
      fi

      echo "🚀 اعمال تنظیمات با netplan..."
      netplan apply
      echo "✅ MTU به‌صورت دائمی برای Netplan تنظیم شد."
    else
      # در سیستم‌هایی که از /etc/network/interfaces استفاده می‌کنند
      if [ -f /etc/network/interfaces ]; then
        echo "📝 در حال ویرایش /etc/network/interfaces..."

        # حذف خط قبلی MTU
        sed -i "/iface $iface inet/,/^$/ s/ *mtu [0-9]*//g" /etc/network/interfaces

        # اضافه کردن خط جدید MTU
        sed -i "/iface $iface inet/,/^$/ s/^$/    mtu 1476\n/" /etc/network/interfaces

        echo "🔄 ریستارت شبکه برای اعمال تغییر..."
        ifdown "$iface" && ifup "$iface" || echo "⚠️ ممکنه نیاز به ریبوت داشته باشید."
        echo "✅ MTU به‌صورت دائمی در ifupdown تنظیم شد."
      else
        echo "⚠ سیستم شناخته نشد. لطفاً به صورت دستی بررسی کنید."
      fi
    fi
    ;;

  centos|rhel|rocky|almalinux)
    cfg_file="/etc/sysconfig/network-scripts/ifcfg-$iface"
    if [ -f "$cfg_file" ]; then
      echo "📝 در حال ویرایش $cfg_file"
      sed -i '/^MTU=/d' "$cfg_file"
      echo "MTU=1476" >> "$cfg_file"
      echo "🔄 ریستارت سرویس شبکه..."
      systemctl restart network || echo "⚠ ممکنه نیاز به ریبوت داشته باشید."
      echo "✅ MTU برای CentOS/RHEL تنظیم شد."
    else
      echo "⚠ فایل پیکربندی $cfg_file پیدا نشد. لطفاً بررسی کنید."
    fi
    ;;

  *)
    echo "⚠ توزیع پشتیبانی نمی‌شود. لطفاً به صورت دستی اعمال کنید."
    ;;
esac

# بررسی نهایی
mtu_now=$(ip link show "$iface" | grep mtu | awk '{print $5}')
echo "📦 مقدار فعلی MTU برای $iface: $mtu_now"

if [ "$mtu_now" = "1476" ]; then
  echo "🎉 عملیات با موفقیت انجام شد!"
else
  echo "❗ MTU هنوز روی 1476 تنظیم نشده. لطفاً بررسی دستی انجام دهید."
fi
